%% verify_calibration_pwelch.m
% Verify that a pure tone at a known acoustic level is correctly recovered
% using the pwelch approach from calibratedPsdExample.m.
%
% Generates a synthetic WAV with a 100 Hz tone at 122 dB re 1 uPa using
% the Kerguelen 2024 instrument chain, then recovers the level using both
% pwelch (your calibration script approach) and snrSpectrogram (bsnr approach).
%
% Run: run('C:\analysis\bsnr\tests\verify_calibration_pwelch.m')

clear; close all;

%% Instrument parameters (Kerguelen 2024)
metadata.hydroSensitivity_dB = -165.9;
metadata.adPeakVolt          = 1.5;
metadata.sampleRate          = 12000;
metadata.frontEndFreq_Hz     = [2 5 10 20 50 100 200 500 1000 2000 5000 10000 20000];
metadata.frontEndGain_dB     = [9.28 15.55 18.47 19.58 19.95 20.01 20.03 20.03 20.04 20.04 12.27 -23.91 -60.10];

trueSigLevel  = 122;   % dB re 1 uPa
trueNoiseLevel = 90;   % dB re 1 uPa
toneFreqHz    = 100;
freq          = [80 120];
sampleRate    = metadata.sampleRate;
durSec        = 60;    % long enough for stable pwelch estimate

fprintf('Target: %d dB re 1 uPa tone at %d Hz\n\n', trueSigLevel, toneFreqHz);

%% Convert to WAV amplitude
gainAtTone = interp1(log10(metadata.frontEndFreq_Hz), metadata.frontEndGain_dB, ...
    log10(toneFreqHz), 'linear', 'extrap');
adPeakdBV  = 20 * log10(metadata.adPeakVolt);

sigDBFS    = trueSigLevel  + metadata.hydroSensitivity_dB + gainAtTone - adPeakdBV;
noiseDBFS  = trueNoiseLevel + metadata.hydroSensitivity_dB + gainAtTone - adPeakdBV;

signalRMS   = 10^(sigDBFS  / 20);   % WAV RMS
noiseRMS_inband = 10^(noiseDBFS / 20);
widebandRMS = noiseRMS_inband * sqrt(sampleRate/2 / diff(freq));

fprintf('Signal WAV amplitude (RMS): %.6f (%.2f dBFS)\n', signalRMS, sigDBFS);
fprintf('Noise wideband RMS:         %.6f\n\n', widebandRMS);

%% Generate audio
rng(42);
nSamples = round(durSec * sampleRate);
t        = (0:nSamples-1)' / sampleRate;
% sqrt(2) so sine RMS = signalRMS
wavData  = signalRMS * sqrt(2) * sin(2*pi*toneFreqHz*t) + widebandRMS * randn(nSamples,1);
wavData  = wavData - mean(wavData);

%% Method 1: pwelch (from calibratedPsdExample.m)
fprintf('=== Method 1: pwelch (calibratedPsdExample approach) ===\n');

nfft     = 2^nextpow2(sampleRate);   % 1s windows
nOverlap = nfft / 2;
win      = hamming(nfft);

[psd, f] = pwelch(wavData, win, nOverlap, nfft, sampleRate);

% Calibration factors (from calibratedPsdExample.m)
adVpeakdB      = 10 * log10(1 / metadata.adPeakVolt^2);
frontEndGain   = interp1(log10(metadata.frontEndFreq_Hz), metadata.frontEndGain_dB, ...
    log10(f + eps), 'linear', 'extrap');
caldB          = metadata.hydroSensitivity_dB + frontEndGain + adVpeakdB;
psdCal_dB      = 10*log10(psd) - caldB;   % calibrated PSD in dB re 1 uPa^2/Hz

% Recover level at tone frequency
[~, toneIdx]   = min(abs(f - toneFreqHz));
fprintf('Tone bin: f=%.2f Hz, PSD=%.1f dB re 1 uPa^2/Hz\n', f(toneIdx), psdCal_dB(toneIdx));

% Band level using bandpower (integrates PSD correctly for tones AND noise)
freqBand = freq;
bandWidthCorrection = -10*log10(diff(freqBand));
bandLevel_psd = pow2db(bandpower(10.^(psdCal_dB/10), f, freqBand, 'psd'));
fprintf('Band level [%d-%d] Hz (bandpower): %.1f dB re 1 uPa (expected %d)\n', ...
    freqBand(1), freqBand(2), bandLevel_psd, trueSigLevel);

% Alternatively: integrate manually
fBandIdx = f >= freq(1) & f <= freq(2);
df       = f(2) - f(1);
bandLevel_manual = 10*log10(sum(10.^(psdCal_dB(fBandIdx)/10)) * df);
fprintf('Band level [%d-%d] Hz (manual sum): %.1f dB re 1 uPa (expected %d)\n', ...
    freq(1), freq(2), bandLevel_manual, trueSigLevel);

% Noise level (in a band away from the tone)
noiseFreqBand = [200 240];
noiseBandIdx  = f >= noiseFreqBand(1) & f <= noiseFreqBand(2);
noiseLevel_pwelch = 10*log10(sum(10.^(psdCal_dB(noiseBandIdx)/10)) * df);
fprintf('Noise level [%d-%d] Hz: %.1f dB re 1 uPa (equivalent to %d dB over [80-120] Hz)\n\n', ...
    noiseFreqBand(1), noiseFreqBand(2), noiseLevel_pwelch, trueNoiseLevel);

%% Method 2: snrSpectrogram (bsnr approach)
fprintf('=== Method 2: snrSpectrogram (bsnr) ===\n');

noiseData = widebandRMS * randn(nSamples, 1);
[rmsS, rmsN, ~] = snrSpectrogram(wavData, noiseData, nfft, nOverlap, sampleRate, freq, metadata);
fprintf('rmsSignal = %.3g uPa^2/Hz, rmsNoise = %.3g uPa^2/Hz\n', rmsS, rmsN);
fprintf('SNR = %.1f dB (expected %d)\n', 10*log10(rmsS/rmsN), trueSigLevel - trueNoiseLevel);

% Level recovery: sum(PSD)*df/bandwidth * bandwidth = sum(PSD)*df
% rmsS = mean(sum(PSD)*df)/bandwidth, so rmsS*bandwidth = mean band power
sigLevel_bsnr   = 10*log10(rmsS);
noiseLevel_bsnr = 10*log10(rmsN);
fprintf('Signal level (bsnr):  %.1f dB re 1 uPa (expected %d)\n', sigLevel_bsnr, trueSigLevel);
fprintf('Noise level  (bsnr):  %.1f dB re 1 uPa (expected %d)\n\n', noiseLevel_bsnr, trueNoiseLevel);

%% Plot calibrated PSD
figure;
semilogx(f(2:end), psdCal_dB(2:end));
hold on;
xline(freq(1), 'r--'); xline(freq(2), 'r--');
xlabel('Frequency (Hz)'); ylabel('PSD (dB re 1 \muPa^2/Hz)');
title(sprintf('Calibrated PSD — %d Hz tone at %d dB re 1 \\muPa', toneFreqHz, trueSigLevel));
grid on; xlim([1 sampleRate/2]);
yline(trueSigLevel - 10*log10(diff(freq)), 'g--', 'Signal spectral level');
fprintf('Expected spectral level at tone: %.1f dB re 1 uPa^2/Hz\n', ...
    trueSigLevel - 10*log10(diff(freq)));
