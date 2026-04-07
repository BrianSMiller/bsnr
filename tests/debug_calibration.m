%% debug_calibration.m
% Standalone calibration verification.
% Run directly in MATLAB: run('C:\analysis\bsnr\tests\debug_calibration.m')

clear; close all;

%% Instrument parameters (Kerguelen 2024)
metadata.hydroSensitivity_dB = -165.9;
metadata.adPeakVolt          = 1.5;
metadata.sampleRate          = 12000;
metadata.frontEndFreq_Hz     = [2 5 10 20 50 100 200 500 1000 2000 5000 10000 20000];
metadata.frontEndGain_dB     = [9.28 15.55 18.47 19.58 19.95 20.01 20.03 20.03 20.04 20.04 12.27 -23.91 -60.10];

%% Known acoustic levels
sigLeveldB   = 122;   % dB re 1 uPa (tone)
noiseLeveldB =  90;   % dB re 1 uPa (in-band noise)
trueSNRdB    = sigLeveldB - noiseLeveldB;   % 32 dB
toneFreqHz   = 100;
freq         = [80 120];   % Hz
sampleRate   = metadata.sampleRate;
durSec       = 10;

fprintf('True SNR = %d dB\n', trueSNRdB);

%% Convert acoustic levels to WAV amplitudes
gainAtTone = interp1(log10(metadata.frontEndFreq_Hz), metadata.frontEndGain_dB, ...
    log10(toneFreqHz), 'linear', 'extrap');
adPeakdBV  = 20 * log10(metadata.adPeakVolt);

% Signal: tone amplitude in WAV units
sigDBFS     = sigLeveldB + metadata.hydroSensitivity_dB + gainAtTone - adPeakdBV;
signalRMS   = 10^(sigDBFS / 20);

% Noise: in-band RMS. Scale wideband noise so in-band RMS = noiseRMS_inband.
% This is the same approach as createTestFixture.
noiseDBFS      = noiseLeveldB + metadata.hydroSensitivity_dB + gainAtTone - adPeakdBV;
noiseRMS_inband = 10^(noiseDBFS / 20);
nyquist         = sampleRate / 2;
bandwidth       = diff(freq);
widebandRMS     = noiseRMS_inband * sqrt(nyquist / bandwidth);

fprintf('Signal amplitude:     %.6f WAV (%.2f dBFS)\n', signalRMS, sigDBFS);
fprintf('Noise in-band RMS:    %.6f WAV (%.2f dBFS)\n', noiseRMS_inband, noiseDBFS);
fprintf('Noise wideband RMS:   %.6f WAV\n', widebandRMS);
fprintf('True in-band SNR:     %.1f dB\n\n', 10*log10(signalRMS^2/2 / noiseRMS_inband^2));

%% Generate audio
rng(42);
nSamples   = round(durSec * sampleRate);
t          = (0:nSamples-1)' / sampleRate;
sigAudio   = signalRMS * sqrt(2) * sin(2*pi*toneFreqHz*t) + widebandRMS * randn(nSamples,1);
noiseAudio = widebandRMS * randn(nSamples, 1);

%% Step 1: snrTimeDomain without calibration
fprintf('--- snrTimeDomain (no calibration) ---\n');
[rmsS, rmsN, ~] = snrTimeDomain(sigAudio, noiseAudio, freq, sampleRate);
fprintf('SNR = %.2f dB (expected ~%.0f)\n\n', 10*log10(rmsS/rmsN), trueSNRdB);

%% Step 2: snrTimeDomain with calibration
fprintf('--- snrTimeDomain (with calibration) ---\n');
[rmsS_cal, rmsN_cal, ~] = snrTimeDomain(sigAudio, noiseAudio, freq, sampleRate, metadata);
fprintf('SNR = %.2f dB (expected ~%.0f)\n', 10*log10(rmsS_cal/rmsN_cal), trueSNRdB);
fprintf('Signal = %.3g uPa^2, Noise = %.3g uPa^2\n\n', rmsS_cal, rmsN_cal);

%% Step 3: snrSpectrogram without calibration
fprintf('--- snrSpectrogram (no calibration) ---\n');
nfft     = 2^nextpow2(floor(durSec / 30 / 0.75 * sampleRate));
nOverlap = floor(nfft * 0.75);
binWidth = sampleRate / nfft;
fVec     = 0 : binWidth : sampleRate/2;
nBins    = sum(fVec >= freq(1) & fVec <= freq(2));
fprintf('nfft=%d, binWidth=%.2f Hz, nBins in band=%d\n', nfft, binWidth, nBins);
[rmsS, rmsN, ~] = snrSpectrogram(sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
fprintf('SNR = %.2f dB (expected ~%.0f)\n\n', 10*log10(rmsS/rmsN), trueSNRdB);

%% Step 4: snrSpectrogram with calibration
fprintf('--- snrSpectrogram (with calibration) ---\n');
[rmsS_cal, rmsN_cal, ~] = snrSpectrogram(sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata);
fprintf('SNR = %.2f dB (expected ~%.0f)\n', 10*log10(rmsS_cal/rmsN_cal), trueSNRdB);
fprintf('Signal = %.3g uPa^2, Noise = %.3g uPa^2\n\n', rmsS_cal, rmsN_cal);

%% Step 5: Full annotationSNR pipeline
fprintf('--- Full annotationSNR pipeline ---\n');
[annot, meta, cleanup] = createCalibratedTestFixture( ...
    'signalLeveldB', sigLeveldB, 'noiseLeveldB', noiseLeveldB, ...
    'toneFreqHz', toneFreqHz, 'freq', freq, 'durationSec', durSec);

spectroParams.pre        = 2;
spectroParams.post       = 2;
spectroParams.yLims      = [0 500];
spectroParams.freq       = freq;
spectroParams.win        = floor(sampleRate / 4);
spectroParams.overlap    = floor(spectroParams.win * 0.75);

for snrType = {'timeDomain', 'spectrogram', 'spectrogramSlices'}
    params = struct('snrType', snrType{1}, 'showClips', false, ...
        'metadata', meta, 'spectroParams', spectroParams, ...
        'freq', freq);
    [snr, rmsS, rmsN, ~, ~] = annotationSNR(annot, params);
    fprintf('%s: SNR=%.1f dB (expected %d)\n', snrType{1}, snr, trueSNRdB);
end

% Also run as vector to get result table with acoustic level columns
fprintf('\n--- Result table with acoustic levels ---\n');
params = struct('snrType', 'timeDomain', 'showClips', false, ...
    'metadata', meta, 'spectroParams', spectroParams, 'freq', freq);
[resultTable, ~, ~, ~, ~] = annotationSNR([annot; annot], params);
disp(resultTable);
if ismember('signalBandLevel_dBuPa', resultTable.Properties.VariableNames)
    fprintf('Signal level: %.1f dB re 1 uPa (expected %d)\n', ...
        resultTable.signalBandLevel_dBuPa(1), sigLeveldB);
    fprintf('Noise level:  %.1f dB re 1 uPa (expected %d)\n', ...
        resultTable.noiseBandLevel_dBuPa(1), noiseLeveldB);
else
    fprintf('signalBandLevel_dBuPa column not found in result table\n');
end
cleanup();
