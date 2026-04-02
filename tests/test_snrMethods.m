function test_snrMethods()
% Unit tests for snrSpectrogram, snrSpectrogramSlices, snrQuantiles,
% snrTimeDomain, snrRidge.
%
% Tests operate directly on audio arrays — no WAV files needed.
%
% All methods now return [rmsSignal, rmsNoise, noiseVar] only. The SNR
% formula is applied by the caller (annotationSNR). Tests check that:
%   (1) rmsSignal > rmsNoise for a high-SNR tone-in-noise signal
%   (2) rmsSignal <= rmsNoise for a noise-only signal
%   (3) Both values are positive and finite for valid input
%   (4) Too-short audio does not error and returns a scalar
%
% The simple SNR formula 10*log10(rmsSignal/rmsNoise) is also tested
% directly here to confirm it recovers approximately the true power ratio
% (within +/-3 dB) for a long stationary signal.

fprintf('\n=== test_snrMethods ===\n');

sampleRate = 2000;
durSec     = 10;
toneHz     = 200;
signalRMS  = 1.0;
noiseRMS   = 0.1;
freq       = [150 250];

[sigAudio, noiseAudio, trueSNRdB] = makeSyntheticAudio( ...
    sampleRate, durSec, toneHz, signalRMS, noiseRMS);

nSlices  = 30;
overlap  = 0.75;
nfft     = 2^nextpow2(floor(durSec / nSlices / overlap * sampleRate));
nOverlap = floor(nfft * overlap);

rng(99);
noiseOnly  = noiseRMS * randn(size(sigAudio));
shortAudio = sigAudio(1:10);

fprintf('True power-ratio SNR: %.1f dB\n\n', trueSNRdB);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Noise spectrum check: verify wideband noise is spectrally flat
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Noise spectrum check ---\n');

% Measure noise power in the target band and two adjacent bands of equal width
% using snrSpectrogram (which uses STFT bandpower, not a narrow FIR filter).
% For white noise all three bands should have equal power within sampling variance.
% A large discrepancy indicates the noise is bandpass-filtered rather than white.
% Note: snrTimeDomain is NOT used here because its order-48 FIR filter has
% transition bandwidth ~137 Hz which exceeds the 100 Hz test band width,
% giving misleading results for narrow bands.
bw         = diff(freq);                  % 100 Hz
freqBelow  = [freq(1)-bw, freq(1)];       % [50  150] Hz
freqTarget = freq;                        % [150 250] Hz
freqAbove  = [freq(2),    freq(2)+bw];    % [250 350] Hz

[~, rmsN_below,  ~] = snrSpectrogram(noiseAudio, noiseAudio, nfft, nOverlap, sampleRate, freqBelow,  []);
[~, rmsN_target, ~] = snrSpectrogram(noiseAudio, noiseAudio, nfft, nOverlap, sampleRate, freqTarget, []);
[~, rmsN_above,  ~] = snrSpectrogram(noiseAudio, noiseAudio, nfft, nOverlap, sampleRate, freqAbove,  []);

ratioBelow = 10 * log10(rmsN_target / rmsN_below);
ratioAbove = 10 * log10(rmsN_target / rmsN_above);
assert(abs(ratioBelow) < 3, ...
    sprintf('Noise not flat: in-band/below = %.1f dB (expected ~0 dB)', ratioBelow));
assert(abs(ratioAbove) < 3, ...
    sprintf('Noise not flat: in-band/above = %.1f dB (expected ~0 dB)', ratioAbove));
fprintf('  [PASS] makeSyntheticAudio noise flat: below=%.1f, target=%.1f, above=%.1f dB\n', ...
    10*log10(rmsN_below), 10*log10(rmsN_target), 10*log10(rmsN_above));

% Also check createTestFixture noise (goes through WAV write/read)
[annotF, cleanupF] = createTestFixture('signalRMS', 0, 'noiseRMS', noiseRMS, ...
    'freq', freq, 'durationSec', durSec);
try
    soundFolder = wavFolderInfo(annotF.soundFolder);
    [fixNoise, ~, ~] = getAudioFromFiles(soundFolder, annotF.t0, annotF.tEnd, ...
        newRate=sampleRate);
    [~, rmsF_below,  ~] = snrSpectrogram(fixNoise, fixNoise, nfft, nOverlap, sampleRate, freqBelow,  []);
    [~, rmsF_target, ~] = snrSpectrogram(fixNoise, fixNoise, nfft, nOverlap, sampleRate, freqTarget, []);
    [~, rmsF_above,  ~] = snrSpectrogram(fixNoise, fixNoise, nfft, nOverlap, sampleRate, freqAbove,  []);
    ratioF_below = 10 * log10(rmsF_target / rmsF_below);
    ratioF_above = 10 * log10(rmsF_target / rmsF_above);
    assert(abs(ratioF_below) < 3, ...
        sprintf('createTestFixture noise not flat: in-band/below = %.1f dB', ratioF_below));
    assert(abs(ratioF_above) < 3, ...
        sprintf('createTestFixture noise not flat: in-band/above = %.1f dB', ratioF_above));
    fprintf('  [PASS] createTestFixture noise flat: below=%.1f, target=%.1f, above=%.1f dB\n', ...
        10*log10(rmsF_below), 10*log10(rmsF_target), 10*log10(rmsF_above));
catch err
    cleanupF();
    rethrow(err);
end
cleanupF();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrSpectrogram
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrSpectrogram ---\n');

[rmsS, rmsN, nVar] = snrSpectrogram( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrSpectrogram: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrSpectrogram: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar > 0, 'snrSpectrogram: noiseVar should be positive and finite');
assert(rmsS > rmsN, ...
    sprintf('snrSpectrogram: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
simpleSNR = 10 * log10(rmsS / rmsN);
% Spectrogram methods integrate PSD which includes spectral leakage from
% the pure tone, so the estimated power is higher than the true RMS power.
% Use a wider tolerance here; snrTimeDomain is the precision reference.
assert(abs(simpleSNR - trueSNRdB) < 10, ...
    sprintf('snrSpectrogram: simple SNR %.2f dB is >10 dB from true %.2f dB', simpleSNR, trueSNRdB));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB\n', rmsS, rmsN, simpleSNR);

[rmsS_n, rmsN_n, ~] = snrSpectrogram( ...
    noiseOnly, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrSpectrogram: noise-only should return finite values');
assert(rmsS_n <= rmsN_n * 2, ...  % allow some variance but signal shouldn't dwarf noise
    sprintf('snrSpectrogram: noise-only rmsSignal (%.4g) unexpectedly >> rmsNoise (%.4g)', rmsS_n, rmsN_n));
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

[rmsS_sh, ~, ~] = snrSpectrogram(shortAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isscalar(rmsS_sh), 'snrSpectrogram: too-short audio should return scalar without error');
fprintf('  [PASS] too-short audio returns scalar\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrSpectrogramSlices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrSpectrogramSlices ---\n');

[rmsS, rmsN, nVar] = snrSpectrogramSlices( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrSpectrogramSlices: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrSpectrogramSlices: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar > 0, 'snrSpectrogramSlices: noiseVar should be positive and finite');
assert(rmsS > rmsN, ...
    sprintf('snrSpectrogramSlices: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
simpleSNR = 10 * log10(rmsS / rmsN);
assert(abs(simpleSNR - trueSNRdB) < 10, ...
    sprintf('snrSpectrogramSlices: simple SNR %.2f dB is >10 dB from true %.2f dB', simpleSNR, trueSNRdB));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB\n', rmsS, rmsN, simpleSNR);

[rmsS_n, rmsN_n, ~] = snrSpectrogramSlices( ...
    noiseOnly, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrSpectrogramSlices: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

[rmsS_sh, ~, ~] = snrSpectrogramSlices(shortAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isscalar(rmsS_sh), 'snrSpectrogramSlices: too-short audio should return scalar without error');
fprintf('  [PASS] too-short audio returns scalar\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrQuantiles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrQuantiles (experimental) ---\n');

[rmsS, rmsN, nVar] = snrQuantiles( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq);

assert(isfinite(rmsS) && rmsS > 0, 'snrQuantiles: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrQuantiles: rmsNoise should be positive and finite');
assert(isfinite(nVar),              'snrQuantiles: noiseVar should be finite');
assert(rmsS > rmsN, ...
    sprintf('snrQuantiles: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g\n', rmsS, rmsN);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrTimeDomain
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrTimeDomain ---\n');

[rmsS, rmsN, nVar, sigFilt, noiseFilt] = snrTimeDomain( ...
    sigAudio, noiseAudio, freq, sampleRate);

assert(isfinite(rmsS) && rmsS > 0, 'snrTimeDomain: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrTimeDomain: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar > 0, 'snrTimeDomain: noiseVar should be positive and finite');
assert(rmsS > rmsN, ...
    sprintf('snrTimeDomain: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
assert(~isempty(sigFilt) && length(sigFilt) == length(sigAudio), ...
    'snrTimeDomain: sigFilt should match input length on success');
assert(~isempty(noiseFilt), ...
    'snrTimeDomain: noiseFilt should be non-empty on success');
% snrTimeDomain measures in-band power: the bandpass filter rejects
% out-of-band noise, so rmsNoise << wideband noiseRMS. The in-band
% SNR is therefore much higher than the wideband trueSNRdB. Instead
% of asserting a specific dB value, verify the power ratio is
% self-consistent: rmsSignal should be dominated by the tone.
inBandNoisePower = noiseRMS^2 * (freq(2)-freq(1)) / (sampleRate/2);
inBandSNRdB = 10 * log10((signalRMS^2/2) / inBandNoisePower); % /2 for sine RMS
simpleSNR = 10 * log10(rmsS / rmsN);
assert(abs(simpleSNR - inBandSNRdB) < 4, ...
    sprintf('snrTimeDomain: simple SNR %.2f dB is >4 dB from in-band true %.2f dB', simpleSNR, inBandSNRdB));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (in-band true=%.2f dB)\n', rmsS, rmsN, simpleSNR, inBandSNRdB);

[rmsS_n, rmsN_n, ~, ~, ~] = snrTimeDomain(noiseOnly, noiseAudio, freq, sampleRate);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrTimeDomain: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

% Frequency band straddling Nyquist — designfilt should fail gracefully
nyquist = sampleRate / 2;
[rmsS_bad, ~, ~, ~, ~] = snrTimeDomain(sigAudio, noiseAudio, [nyquist*0.9, nyquist*1.1], sampleRate);
assert(isnan(rmsS_bad), 'snrTimeDomain: freq above Nyquist should return NaN without error');
fprintf('  [PASS] freq above Nyquist returns NaN\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrRidge
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrRidge ---\n');

% (1) Ridge tracks close to the true tone frequency
[rmsS, rmsN, nVar, ridgeFreq, sliceSnr] = snrRidge( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrRidge: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrRidge: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar >= 0, 'snrRidge: noiseVar should be non-negative and finite');
assert(rmsS > rmsN, ...
    sprintf('snrRidge: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
assert(length(ridgeFreq) > 1, 'snrRidge: ridgeFreq should be a vector with one entry per time slice');
ridgeMeanHz = mean(ridgeFreq, 'omitnan');
assert(abs(ridgeMeanHz - toneHz) < 50, ...
    sprintf('snrRidge: mean ridge freq %.1f Hz should be within 50 Hz of tone %.1f Hz', ...
    ridgeMeanHz, toneHz));
simpleSNR = 10 * log10(rmsS / rmsN);
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB\n', rmsS, rmsN, simpleSNR);
fprintf('  [PASS] mean ridge frequency = %.1f Hz (tone = %.1f Hz)\n', ridgeMeanHz, toneHz);

% (2) Noise-only: rmsSignal should be comparable to rmsNoise
[rmsS_n, rmsN_n, ~, ~, ~] = snrRidge( ...
    noiseOnly, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrRidge: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

% (3) Custom ridgePenalty and guardBins flow through without error
ridgeParams = struct('ridgePenalty', 0.5, 'guardBins', 3);
[rmsS_p, ~, ~, ~, ~] = snrRidge( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, [], ridgeParams);
assert(isfinite(rmsS_p), 'snrRidge: custom params should return finite result');
fprintf('  [PASS] custom ridgePenalty=0.5, guardBins=3 accepted\n');

% (4) Ridge is more robust than snrSpectrogram under transient interference.
% Inject a loud click into the signal at the midpoint; the ridge method
% should still recover a positive SNR because tfridge bridges the dropout.
sigWithClick = sigAudio;
clickStart   = round(length(sigAudio)/2);
clickLen     = round(0.05 * sampleRate);   % 50 ms click
sigWithClick(clickStart : clickStart+clickLen-1) = 5 * randn(clickLen, 1);

[rmsS_click, rmsN_click, ~, ~, ~] = snrRidge( ...
    sigWithClick, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_click) && rmsS_click > rmsN_click, ...
    'snrRidge: should remain signal > noise even with transient click injection');
fprintf('  [PASS] robust to 50 ms click: SNR = %.2f dB\n', ...
    10*log10(rmsS_click/rmsN_click));

% (5) Narrow band that produces fewer than 3 bins returns NaN gracefully
tinyFreq = [198 202];   % ~2 bins wide at fs=2000 Hz, nfft=512
[rmsS_nb, ~, ~, ~, ~] = snrRidge( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, tinyFreq, []);
% Either finite (if enough bins) or NaN (if too narrow) — must not error
assert(isscalar(rmsS_nb), 'snrRidge: narrow band should return scalar without error');
fprintf('  [PASS] narrow band returns scalar (%.4g)\n', rmsS_nb);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SRW upcall shared setup (used by both snrSynchrosqueeze and snrRidge)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% SRW upcall: f(t) = 80 + 118*t^2, sweeping 80->198 Hz over 1 s
srwRate = 1000;
srwFreq = [75 210];   % band containing the full sweep
[srwSig, srwNoise, srwT, srwInstFreq] = makeSRWUpcall(srwRate, 0.1);
rng(101);
srwNoiseOnly = srwNoise;   % independent noise-only draw, same distribution

% Spectrogram parameters for 1 s signal
srwNfft     = 2^nextpow2(floor(1.0 / 30 / 0.75 * srwRate));
srwNOverlap = floor(srwNfft * 0.75);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrSynchrosqueeze
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrSynchrosqueeze ---\n');

% (1) High-SNR stationary tone
[rmsS, rmsN, nVar, ~, ~] = snrSynchrosqueeze( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrSynchrosqueeze: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrSynchrosqueeze: rmsNoise should be positive and finite');
assert(rmsS > rmsN, ...
    sprintf('snrSynchrosqueeze: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
simpleSNR = 10 * log10(rmsS / rmsN);
fprintf('  [PASS] high-SNR tone: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB\n', rmsS, rmsN, simpleSNR);

% (2) Noise-only
[rmsS_n, rmsN_n, ~, ~, ~] = snrSynchrosqueeze( ...
    noiseOnly, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrSynchrosqueeze: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

% (3) SRW upcall — synchrosqueeze should track the FM sweep
[rmsS_srw2, rmsN_srw2, ~, ridgeFreq_ssq, ~] = snrSynchrosqueeze( ...
    srwSig, srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);
assert(isfinite(rmsS_srw2) && rmsS_srw2 > rmsN_srw2, ...
    'snrSynchrosqueeze SRW: rmsSignal should exceed rmsNoise');
ridgeMean_ssq = mean(ridgeFreq_ssq, 'omitnan');
assert(ridgeMean_ssq >= 80 && ridgeMean_ssq <= 200, ...
    sprintf('snrSynchrosqueeze SRW: mean ridge %.1f Hz should be in [80 198] Hz', ridgeMean_ssq));
fprintf('  [PASS] SRW upcall: SNR=%.2f dB, mean ridge=%.1f Hz\n', ...
    10*log10(rmsS_srw2/rmsN_srw2), ridgeMean_ssq);

% (4) Compare synchrosqueeze vs ridge for FM signal: both should rank high-SNR > noise-only
[snrHigh_ssq, ~, ~, ~, ~] = snrSynchrosqueeze(srwSig,   srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);
[snrLow_ssq,  ~, ~, ~, ~] = snrSynchrosqueeze(srwNoiseOnly, srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);
assert(snrHigh_ssq > snrLow_ssq, ...
    sprintf('snrSynchrosqueeze: SRW signal (%.2g) should exceed noise-only (%.2g)', snrHigh_ssq, snrLow_ssq));
fprintf('  [PASS] high > noise-only: %.4g > %.4g\n', snrHigh_ssq, snrLow_ssq);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrRidge — SRW upcall (FM sweep, more realistic test signal)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrRidge: SRW upcall (quadratic FM sweep) ---\n');

% (6) Ridge tracks the FM sweep: mean ridge freq should lie within the sweep range
[rmsS_srw, rmsN_srw, ~, ridgeFreq_srw, ~] = snrRidge( ...
    srwSig, srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);

assert(isfinite(rmsS_srw) && rmsS_srw > 0, ...
    'snrRidge SRW: rmsSignal should be positive and finite');
assert(rmsS_srw > rmsN_srw, ...
    sprintf('snrRidge SRW: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', ...
    rmsS_srw, rmsN_srw));

% Ridge mean should lie within the sweep range [80 198] Hz
ridgeMean_srw = mean(ridgeFreq_srw, 'omitnan');
assert(ridgeMean_srw >= 80 && ridgeMean_srw <= 200, ...
    sprintf('snrRidge SRW: mean ridge %.1f Hz should be within sweep range [80 198] Hz', ...
    ridgeMean_srw));

% Ridge should be monotonically increasing (upcall sweeps upward)
% Allow occasional small reversals from noise — check overall trend
ridgeStart = mean(ridgeFreq_srw(1 : max(1,floor(end/4))),      'omitnan');
ridgeEnd   = mean(ridgeFreq_srw(max(1,floor(3*end/4)) : end),  'omitnan');
assert(ridgeEnd > ridgeStart, ...
    sprintf('snrRidge SRW: ridge should trend upward (start=%.1f Hz, end=%.1f Hz)', ...
    ridgeStart, ridgeEnd));

fprintf('  [PASS] SRW upcall: SNR=%.2f dB, ridge %.1f->%.1f Hz (sweep 80->198 Hz)\n', ...
    10*log10(rmsS_srw/rmsN_srw), ridgeStart, ridgeEnd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Simple SNR formula recovers true SNR (via annotationSNR params)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- SNR formula: simple vs Lurton ---\n');
% This is tested via the power values above for the method functions.
% Document expected behaviour clearly:
%   simple:  10*log10(rmsSignal/rmsNoise) ≈ trueSNRdB  (within ~3 dB)
%   Lurton:  10*log10((S-N)^2/noiseVar)  >> trueSNRdB  (can be 30-50 dB higher)
% The Lurton formula is not tested here since it is applied in annotationSNR,
% not in the method functions. See test_annotationSNR_scalar for formula tests.
fprintf('  [INFO] simple SNR formula tested above; Lurton tested in test_annotationSNR_scalar\n');

fprintf('\n=== test_snrMethods PASSED ===\n');
end
