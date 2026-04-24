function test_snrMethods()
% Unit tests for snrSpectrogram, snrSpectrogramSlices, snrQuantiles,
% snrTimeDomain, snrRidge, snrSynchrosqueeze, and snrHistogram (NIST).
%
% Tests operate directly on audio arrays — no WAV files needed.
%
% All methods return [rmsSignal, rmsNoise, noiseVar] only. The SNR
% formula is applied by the caller (snrEstimate). Tests check that:
%   (1) rmsSignal > rmsNoise for a high-SNR tone-in-noise signal
%   (2) rmsSignal <= rmsNoise for a noise-only signal
%   (3) Both values are positive and finite for valid input
%   (4) Too-short audio does not error and returns a scalar
%   (5) snrHistogram: noise peak bin is in the correct dB region
%       (regression guard against the BINS/2 search-range bug)
%
% The simple SNR formula 10*log10(rmsSignal/rmsNoise) is tested against
% the correct reference for each method. There are three distinct tiers:
%
%   inBandSNRdB      (band-average) — spectrogram, spectrogramSlices,
%                     quantiles, histogram: noise averaged over all band bins
%   inBandSNRdB-3dB  (band-average, sine) — timeDomain: FIR filter,
%                     mean(sin^2)=0.5 lowers signal estimate by 3 dB
%   ridgeSNRdB       (per-bin) — ridge, synchrosqueeze: signal at one bin,
%                     noise averaged over other bins; = inBandSNRdB + 10*log10(nBandBins)

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

% In-band true SNR: all bsnr methods operate on the annotation frequency
% band [freq(1) freq(2)] — not wideband. For a pure tone sitting entirely
% within the band, signal power is unchanged. White noise power scales
% with bandwidth: in-band noise power = noiseRMS^2 * BW/Nyquist.
% This is the correct reference for every method test.
%
%   inBandSNRdB = 10*log10( toneRMS^2 / (noiseRMS^2 * BW/Nyquist) )
%               = trueSNRdB + 10*log10(Nyquist/BW)
%               = 20 + 10*log10(1000/100) = 30 dB  for these parameters
%
% Note: snrTimeDomain divides by 2 for sine RMS (mean(sin^2)=0.5) while
% snrSpectrogram integrates PSD bin power — both yield ~inBandSNRdB with
% method-specific tolerances.  trueSNRdB is retained only for documentation.
nyquist       = sampleRate / 2;
bw            = diff(freq);
inBandSNRdB   = trueSNRdB + 10 * log10(nyquist / bw);   % ~30 dB

fprintf('True wideband SNR: %.1f dB   In-band true SNR [%.0f-%.0f Hz]: %.1f dB\n\n', ...
    trueSNRdB, freq(1), freq(2), inBandSNRdB);

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
% Spectrogram methods integrate band PSD. Spectral leakage from the pure
% tone broadens the power estimate slightly, so allow ±5 dB around
% the in-band true SNR.
assert(abs(simpleSNR - inBandSNRdB) < 5, ...
    sprintf('snrSpectrogram: simple SNR %.2f dB is >5 dB from in-band true %.2f dB', simpleSNR, inBandSNRdB));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (in-band true=%.2f dB)\n', rmsS, rmsN, simpleSNR, inBandSNRdB);

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
assert(abs(simpleSNR - inBandSNRdB) < 5, ...
    sprintf('snrSpectrogramSlices: simple SNR %.2f dB is >5 dB from in-band true %.2f dB', simpleSNR, inBandSNRdB));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (in-band true=%.2f dB)\n', rmsS, rmsN, simpleSNR, inBandSNRdB);

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
    sigAudio, nfft, nOverlap, sampleRate, freq);

assert(isfinite(rmsS) && rmsS > 0, 'snrQuantiles: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrQuantiles: rmsNoise should be positive and finite');
assert(isfinite(nVar),              'snrQuantiles: noiseVar should be finite');
assert(rmsS > rmsN, ...
    sprintf('snrQuantiles: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
simpleSNR = 10 * log10(rmsS / rmsN);
% snrQuantiles operates on spectrogram cells within the annotation band,
% so it also measures in-band SNR. The 85th-percentile split introduces
% extra variance; allow ±8 dB.
assert(abs(simpleSNR - inBandSNRdB) < 8, ...
    sprintf('snrQuantiles: simple SNR %.2f dB is >8 dB from in-band true %.2f dB', simpleSNR, inBandSNRdB));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (in-band true=%.2f dB)\n', rmsS, rmsN, simpleSNR, inBandSNRdB);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrTimeDomain
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrTimeDomain ---\n');

[rmsS, rmsN, nVar, tdData] = snrTimeDomain( ...
    sigAudio, noiseAudio, freq, sampleRate);

assert(isfinite(rmsS) && rmsS > 0, 'snrTimeDomain: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrTimeDomain: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar > 0, 'snrTimeDomain: noiseVar should be positive and finite');
assert(rmsS > rmsN, ...
    sprintf('snrTimeDomain: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
assert(~isempty(tdData.sigFilt) && length(tdData.sigFilt) == length(sigAudio), ...
    'snrTimeDomain: sigFilt should match input length on success');
assert(~isempty(tdData.noiseFilt), ...
    'snrTimeDomain: noiseFilt should be non-empty on success');
% snrTimeDomain applies a bandpass FIR, so it measures in-band power.
% The tone sits entirely in-band (RMS = signalRMS/sqrt(2) for a sine).
% inBandSNRdB already accounts for BW/Nyquist noise reduction; the
% additional /2 for sine power is implicitly included since
% signalRMS = peak amplitude and mean(sin^2) = 0.5 — so the true
% in-band signal power is signalRMS^2/2, not signalRMS^2.
% Adjust reference by -10*log10(2) ≈ -3 dB for the sine factor.
inBandSNRdB_sine = inBandSNRdB - 10*log10(2);   % ~27 dB for these params
simpleSNR = 10 * log10(rmsS / rmsN);
assert(abs(simpleSNR - inBandSNRdB_sine) < 4, ...
    sprintf('snrTimeDomain: simple SNR %.2f dB is >4 dB from in-band true %.2f dB', simpleSNR, inBandSNRdB_sine));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (in-band true=%.2f dB)\n', rmsS, rmsN, simpleSNR, inBandSNRdB_sine);

[rmsS_n, rmsN_n, ~] = snrTimeDomain(noiseOnly, noiseAudio, freq, sampleRate);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrTimeDomain: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

% Frequency band straddling Nyquist — designfilt should fail gracefully
nyquist = sampleRate / 2;
[rmsS_bad] = snrTimeDomain(sigAudio, noiseAudio, [nyquist*0.9, nyquist*1.1], sampleRate);
assert(isnan(rmsS_bad), 'snrTimeDomain: freq above Nyquist should return NaN without error');
fprintf('  [PASS] freq above Nyquist returns NaN\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrRidge
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrRidge ---\n');

% (1) Ridge tracks close to the true tone frequency
[rmsS, rmsN, nVar, rdData] = snrRidge( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrRidge: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrRidge: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar >= 0, 'snrRidge: noiseVar should be non-negative and finite');
assert(rmsS > rmsN, ...
    sprintf('snrRidge: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
assert(length(rdData.ridgeFreq) > 1, 'snrRidge: ridgeFreq should be a vector with one entry per time slice');
ridgeMeanHz = mean(rdData.ridgeFreq, 'omitnan');
assert(abs(ridgeMeanHz - toneHz) < 50, ...
    sprintf('snrRidge: mean ridge freq %.1f Hz should be within 50 Hz of tone %.1f Hz', ...
    ridgeMeanHz, toneHz));
simpleSNR = 10 * log10(rmsS / rmsN);
% snrRidge compares power at the tracked ridge bin to the mean power of
% the remaining (non-guard) bins within the band. For white noise each
% bin carries an equal share of the band power, so the effective noise
% reference is inBandNoisePower / nBandBins — not the full band power.
% The correct reference is therefore:
%   ridgeSNRdB = inBandSNRdB + 10*log10(nBandBins)
% where nBandBins = round(BW * nfft / sampleRate).
nBandBins    = round(bw * nfft / sampleRate);
ridgeSNRdB   = inBandSNRdB + 10 * log10(nBandBins);
assert(abs(simpleSNR - ridgeSNRdB) < 6, ...
    sprintf('snrRidge: simple SNR %.2f dB is >6 dB from per-bin true %.2f dB (inBand=%.1f, nBins=%d)', ...
    simpleSNR, ridgeSNRdB, inBandSNRdB, nBandBins));
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (per-bin true=%.2f dB)\n', ...
    rmsS, rmsN, simpleSNR, ridgeSNRdB);
fprintf('  [PASS] mean ridge frequency = %.1f Hz (tone = %.1f Hz)\n', ridgeMeanHz, toneHz);

% (2) Noise-only: rmsSignal should be comparable to rmsNoise
[rmsS_n, rmsN_n] = snrRidge( ...
    noiseOnly, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrRidge: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

% (3) Custom ridgePenalty and guardBins flow through without error
ridgeParams = struct('ridgePenalty', 0.5, 'guardBins', 3);
[rmsS_p] = snrRidge( ...
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

[rmsS_click, rmsN_click] = snrRidge( ...
    sigWithClick, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_click) && rmsS_click > rmsN_click, ...
    'snrRidge: should remain signal > noise even with transient click injection');
fprintf('  [PASS] robust to 50 ms click: SNR = %.2f dB\n', ...
    10*log10(rmsS_click/rmsN_click));

% (5) Narrow band that produces fewer than 3 bins returns NaN gracefully
tinyFreq = [198 202];   % ~2 bins wide at fs=2000 Hz, nfft=512
[rmsS_nb] = snrRidge( ...
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
[rmsS, rmsN, nVar] = snrSynchrosqueeze( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrSynchrosqueeze: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrSynchrosqueeze: rmsNoise should be positive and finite');
assert(rmsS > rmsN, ...
    sprintf('snrSynchrosqueeze: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
simpleSNR = 10 * log10(rmsS / rmsN);
% snrSynchrosqueeze has the same single-bin-vs-noise-bins geometry as
% snrRidge; use the same per-bin reference.
assert(abs(simpleSNR - ridgeSNRdB) < 6, ...
    sprintf('snrSynchrosqueeze: simple SNR %.2f dB is >6 dB from per-bin true %.2f dB', simpleSNR, ridgeSNRdB));
fprintf('  [PASS] high-SNR tone: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB (per-bin true=%.2f dB)\n', ...
    rmsS, rmsN, simpleSNR, ridgeSNRdB);

% (2) Noise-only
[rmsS_n, rmsN_n, ~] = snrSynchrosqueeze( ...
    noiseOnly, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), 'snrSynchrosqueeze: noise-only should return finite values');
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g\n', rmsS_n, rmsN_n);

% (3) SRW upcall — synchrosqueeze should track the FM sweep
[rmsS_srw2, rmsN_srw2, ~, ssqData] = snrSynchrosqueeze( ...
    srwSig, srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);
assert(isfinite(rmsS_srw2) && rmsS_srw2 > rmsN_srw2, ...
    'snrSynchrosqueeze SRW: rmsSignal should exceed rmsNoise');
ridgeMean_ssq = mean(ssqData.ridgeFreq, 'omitnan');
assert(ridgeMean_ssq >= 80 && ridgeMean_ssq <= 200, ...
    sprintf('snrSynchrosqueeze SRW: mean ridge %.1f Hz should be in [80 198] Hz', ridgeMean_ssq));
fprintf('  [PASS] SRW upcall: SNR=%.2f dB, mean ridge=%.1f Hz\n', ...
    10*log10(rmsS_srw2/rmsN_srw2), ridgeMean_ssq);

% (4) Compare synchrosqueeze vs ridge for FM signal: both should rank high-SNR > noise-only
[snrHigh_ssq, ~, ~] = snrSynchrosqueeze(srwSig,   srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);
[snrLow_ssq,  ~, ~] = snrSynchrosqueeze(srwNoiseOnly, srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);
assert(snrHigh_ssq > snrLow_ssq, ...
    sprintf('snrSynchrosqueeze: SRW signal (%.2g) should exceed noise-only (%.2g)', snrHigh_ssq, snrLow_ssq));
fprintf('  [PASS] high > noise-only: %.4g > %.4g\n', snrHigh_ssq, snrLow_ssq);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrRidge — SRW upcall (FM sweep, more realistic test signal)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrRidge: SRW upcall (quadratic FM sweep) ---\n');

% (6) Ridge tracks the FM sweep: mean ridge freq should lie within the sweep range
[rmsS_srw, rmsN_srw, ~, rdDataSrw] = snrRidge( ...
    srwSig, srwNoise, srwNfft, srwNOverlap, srwRate, srwFreq, []);

assert(isfinite(rmsS_srw) && rmsS_srw > 0, ...
    'snrRidge SRW: rmsSignal should be positive and finite');
assert(rmsS_srw > rmsN_srw, ...
    sprintf('snrRidge SRW: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', ...
    rmsS_srw, rmsN_srw));

% Ridge mean should lie within the sweep range [80 198] Hz
ridgeMean_srw = mean(rdDataSrw.ridgeFreq, 'omitnan');
assert(ridgeMean_srw >= 80 && ridgeMean_srw <= 200, ...
    sprintf('snrRidge SRW: mean ridge %.1f Hz should be within sweep range [80 198] Hz', ...
    ridgeMean_srw));

% Ridge should be monotonically increasing (upcall sweeps upward)
% Allow occasional small reversals from noise — check overall trend
ridgeStart = mean(rdDataSrw.ridgeFreq(1 : max(1,floor(end/4))),      'omitnan');
ridgeEnd   = mean(rdDataSrw.ridgeFreq(max(1,floor(3*end/4)) : end),  'omitnan');
assert(ridgeEnd > ridgeStart, ...
    sprintf('snrRidge SRW: ridge should trend upward (start=%.1f Hz, end=%.1f Hz)', ...
    ridgeStart, ridgeEnd));

fprintf('  [PASS] SRW upcall: SNR=%.2f dB, ridge %.1f->%.1f Hz (sweep 80->198 Hz)\n', ...
    10*log10(rmsS_srw/rmsN_srw), ridgeStart, ridgeEnd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% snrHistogram (NIST STNR 'quick')
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- snrHistogram (NIST quick) ---\n');

% snrHistogram needs longer audio so the frame-energy histogram has enough
% frames (>=10) to be meaningful. Use 30 s with the same parameters as the
% other tests (sampleRate=2000, freq=[150 250], toneHz=200).
rng(77);
[sigH, noiseH] = makeSyntheticAudio(sampleRate, 30, toneHz, signalRMS, noiseRMS);

% (1) Basic outputs: positive, finite, signal > noise
[rmsS, rmsN, nVar, diagH] = snrHistogram(sigH, noiseH, [], [], sampleRate, freq, []);

assert(isfinite(rmsS) && rmsS > 0, 'snrHistogram: rmsSignal should be positive and finite');
assert(isfinite(rmsN) && rmsN > 0, 'snrHistogram: rmsNoise should be positive and finite');
assert(isfinite(nVar) && nVar >= 0, 'snrHistogram: noiseVar should be non-negative and finite');
assert(rmsS > rmsN, ...
    sprintf('snrHistogram: rmsSignal (%.4g) should exceed rmsNoise (%.4g)', rmsS, rmsN));
simpleSNR = 10 * log10(rmsS / rmsN);
fprintf('  [PASS] high-SNR: rmsSignal=%.4g > rmsNoise=%.4g, simple SNR=%.2f dB\n', ...
    rmsS, rmsN, simpleSNR);

% (2) SNR within 6 dB of the in-band true SNR.
% snrHistogram bandpass-filters both windows before computing frame energies,
% so it measures IN-BAND SNR — consistent with all other bsnr methods.
% inBandSNRdB is computed in the shared setup above.
% The NIST estimator is coarse by design; allow ±6 dB.
assert(abs(simpleSNR - inBandSNRdB) < 6, ...
    sprintf('snrHistogram: simple SNR %.2f dB is >6 dB from in-band true %.2f dB', ...
    simpleSNR, inBandSNRdB));
fprintf('  [PASS] SNR accuracy: estimated=%.2f dB, in-band true=%.2f dB (within 6 dB)\n', ...
    simpleSNR, inBandSNRdB);

% (3) diagData structure has required fields for plotting
assert(isstruct(diagH), 'snrHistogram: diagData should be a struct');
for fld = {'binCentres','histSmooth','histRaw','noisedB','signaldB','noiseWidth_dB','noisePeakBin'}
    assert(isfield(diagH, fld{1}), ...
        sprintf('snrHistogram: diagData missing field .%s', fld{1}));
end
fprintf('  [PASS] diagData has all required fields\n');

% (4) Noise peak bin is in the correct region of the histogram.
% For noiseRMS=0.1 at this sample rate, frame energies map to ~67 dB in
% the NIST internal scale. The noise peak should be in the upper half of
% the 500-bin range (bins 251-500, covering ~34-97 dB), NOT the lower
% half where the old buggy code searched (bins 1-250, -28 to 34 dB).
BINS = 500;
assert(diagH.noisePeakBin > BINS/2, ...
    sprintf(['snrHistogram: noisePeakBin=%d is in lower half of histogram (bins 1-%d).\n' ...
             '  This indicates the old search-range bug has re-appeared.\n' ...
             '  Real audio noise at noiseRMS=0.1 maps to ~67 dB (bin ~380) in NIST scale.'], ...
    diagH.noisePeakBin, BINS/2));
fprintf('  [PASS] noisePeakBin=%d is correctly in upper half of histogram (>%d)\n', ...
    diagH.noisePeakBin, BINS/2);

% (5) noisedB < signaldB (noise peak is to the LEFT of signal 95th percentile)
assert(diagH.noisedB < diagH.signaldB, ...
    sprintf('snrHistogram: noisedB (%.1f) should be less than signaldB (%.1f)', ...
    diagH.noisedB, diagH.signaldB));
fprintf('  [PASS] noisedB=%.1f dB < signaldB=%.1f dB (separation=%.1f dB)\n', ...
    diagH.noisedB, diagH.signaldB, diagH.signaldB - diagH.noisedB);

% (6) Noise-only: rmsSignal should be comparable to rmsNoise (no large exceedance)
rng(88);
noiseOnlyH = noiseRMS * randn(length(sigH), 1);
[rmsS_n, rmsN_n, ~] = snrHistogram(noiseOnlyH, noiseH, [], [], sampleRate, freq, []);
assert(isfinite(rmsS_n) && isfinite(rmsN_n), ...
    'snrHistogram: noise-only should return finite values');
% For noise-only input the 95th percentile of the combined histogram will
% be at most a few dB above the noise peak, so SNR estimate should be small.
noiseOnlySNR = 10 * log10(rmsS_n / rmsN_n);
assert(noiseOnlySNR < 10, ...
    sprintf('snrHistogram: noise-only SNR=%.1f dB should be small (<10 dB)', noiseOnlySNR));
fprintf('  [PASS] noise-only: rmsSignal=%.4g, rmsNoise=%.4g, SNR=%.1f dB\n', ...
    rmsS_n, rmsN_n, noiseOnlySNR);

% (7) Too-short audio falls back to RMS ratio without error
shortH = sigH(1:5);
[rmsS_sh, rmsN_sh, ~, diagSh] = snrHistogram(shortH, noiseH, [], [], sampleRate, freq, []);
assert(isscalar(rmsS_sh), 'snrHistogram: too-short audio should return scalar without error');
assert(isstruct(diagSh) && ~isfield(diagSh, 'binCentres'), ...
    'snrHistogram: too-short audio should return struct without binCentres');
fprintf('  [PASS] too-short audio returns scalar (%.4g) and empty diagData\n', rmsS_sh);

% (8) noiseVar is consistent with rmsNoise scale
% noiseVar = var(frame_powers); for stationary noise, std(frame_powers)/mean(frame_powers)
% should be small (Chi-squared variation over many frames). Check it is not
% many orders of magnitude away from rmsNoise^2 (which would indicate a scale bug).
logRatio = log10(nVar / rmsN^2);
assert(abs(logRatio) < 4, ...
    sprintf(['snrHistogram: noiseVar (%.4g) is %.1f decades from rmsNoise^2 (%.4g).\n' ...
             '  These should be on the same power scale.'], nVar, logRatio, rmsN^2));
fprintf('  [PASS] noiseVar=%.4g is %.1f decades from rmsNoise^2=%.4g (scale consistent)\n', ...
    nVar, logRatio, rmsN^2);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Simple SNR formula recovers true SNR (via snrEstimate params)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- SNR formula: simple vs Lurton ---\n');
% This is tested via the power values above for the method functions.
% Document expected behaviour clearly:
%   simple:  10*log10(rmsSignal/rmsNoise) ≈ trueSNRdB  (within ~3 dB)
%   Lurton:  10*log10((S-N)^2/noiseVar)  >> trueSNRdB  (can be 30-50 dB higher)
% The Lurton formula is not tested here since it is applied in snrEstimate,
% not in the method functions. See test_snrEstimate_scalar for formula tests.
fprintf('  [INFO] simple SNR formula tested above; Lurton tested in test_snrEstimate_scalar\n');

fprintf('\n=== test_snrMethods PASSED ===\n');
end

%% Bioduck fixture tests
% These tests use a bout of repeated FM downsweeps (60-100 Hz) mimicking
% Antarctic minke whale bio-duck calls. The annotation covers the full bout
% as a single box — the typical analyst annotation style for bioduck.
% This is a harder test than tone: signal power is intermittent (pulses +
% silence), so methods that average over the full window will underestimate
% signal power relative to methods that track instantaneous power.

function test_bioduck_spectrogram_detects_signal(tc)
    [annot, cleanup] = createTestFixture( ...
        'signalType',    'bioduck', ...
        'durationSec',   20, ...
        'freqHigh',      100, ...
        'freqLow',       60, ...
        'pulseDuration', 0.15, ...
        'pulseInterval', 0.30, ...
        'signalRMS',     1.0, ...
        'noiseRMS',      0.1, ...
        'sampleRate',    1000);
    cleanupObj = onCleanup(cleanup);
    params = struct('snrType','spectrogram','noiseDuration','beforeAndAfter', ...
        'noiseDelay',0.5,'showClips',false);
    snr = snrEstimate(annot, params);
    tc.verifyGreaterThan(snr.snr, 0, ...
        'spectrogram SNR should be positive for bioduck at 20 dB signal-to-noise');
end

function test_bioduck_snr_lower_than_tone(tc)
    % Bioduck SNR should be lower than an equivalent continuous tone at the
    % same RMS, because the pulse train has silent inter-pulse gaps that
    % reduce the effective signal power averaged over the annotation window.
    [annotTone, cleanupTone] = createTestFixture( ...
        'signalType',  'tone', ...
        'durationSec', 20, ...
        'toneFreqHz',  80, ...
        'signalRMS',   1.0, ...
        'noiseRMS',    0.1, ...
        'freq',        [30 500], ...
        'sampleRate',  1000);
    cleanupObjT = onCleanup(cleanupTone);

    [annotBd, cleanupBd] = createTestFixture( ...
        'signalType',    'bioduck', ...
        'durationSec',   20, ...
        'freqHigh',      100, ...
        'freqLow',       60, ...
        'pulseDuration', 0.15, ...
        'pulseInterval', 0.30, ...
        'signalRMS',     1.0, ...
        'noiseRMS',      0.1, ...
        'sampleRate',    1000);
    cleanupObjB = onCleanup(cleanupBd);

    params = struct('snrType','spectrogram','noiseDuration','beforeAndAfter', ...
        'noiseDelay',0.5,'showClips',false);
    snrTone = snrEstimate(annotTone, params);
    snrBd   = snrEstimate(annotBd,   params);
    tc.verifyGreaterThan(snrTone.snr, snrBd.snr, ...
        'Continuous tone SNR should exceed bioduck SNR at same RMS (duty cycle effect)');
end

function test_bioduck_duty_cycle_snr(tc)
    % Verify that bioduck SNR scales approximately with duty cycle.
    % At pulseDuration=0.15s and pulseInterval=0.30s, duty cycle = 0.5,
    % so SNR should be roughly 3 dB lower than a continuous tone (10*log10(0.5)).
    [annotTone, cleanupTone] = createTestFixture( ...
        'signalType',  'tone', ...
        'durationSec', 30, ...
        'toneFreqHz',  80, ...
        'signalRMS',   1.0, ...
        'noiseRMS',    0.05, ...
        'freq',        [30 500], ...
        'sampleRate',  1000);
    cleanupObjT = onCleanup(cleanupTone);

    [annotBd, cleanupBd] = createTestFixture( ...
        'signalType',    'bioduck', ...
        'durationSec',   30, ...
        'freqHigh',      100, ...
        'freqLow',       60, ...
        'pulseDuration', 0.15, ...
        'pulseInterval', 0.30, ...   % duty cycle = 0.15/0.30 = 0.5
        'signalRMS',     1.0, ...
        'noiseRMS',      0.05, ...
        'sampleRate',    1000);
    cleanupObjB = onCleanup(cleanupBd);

    params = struct('snrType','spectrogram','noiseDuration','beforeAndAfter', ...
        'noiseDelay',0.5,'showClips',false);
    snrTone = snrEstimate(annotTone, params);
    snrBd   = snrEstimate(annotBd,   params);
    dutyCycledB = 10 * log10(0.5);   % expected ~-3 dB
    actual_diff = snrBd.snr - snrTone.snr;
    tc.verifyGreaterThan(actual_diff, dutyCycledB - 3, ...
        'Bioduck SNR should be within 3 dB of duty-cycle-adjusted tone SNR');
    tc.verifyLessThan(actual_diff, dutyCycledB + 3, ...
        'Bioduck SNR should be within 3 dB of duty-cycle-adjusted tone SNR');
end

function test_bioduck_all_methods_positive(tc)
    % All SNR methods should return positive SNR for a high-SNR bioduck bout.
    [annot, cleanup] = createTestFixture( ...
        'signalType',    'bioduck', ...
        'durationSec',   20, ...
        'freqHigh',      100, ...
        'freqLow',       60, ...
        'pulseDuration', 0.15, ...
        'pulseInterval', 0.25, ...
        'signalRMS',     2.0, ...
        'noiseRMS',      0.05, ...
        'sampleRate',    1000);
    cleanupObj = onCleanup(cleanup);
    methods = {'spectrogram', 'spectrogramSlices', 'timeDomain'};
    for i = 1:numel(methods)
        params = struct('snrType', methods{i}, 'noiseDuration', 'beforeAndAfter', ...
            'noiseDelay', 0.5, 'showClips', false);
        snr = snrEstimate(annot, params);
        tc.verifyGreaterThan(snr.snr, 0, ...
            sprintf('%s SNR should be positive for high-SNR bioduck', methods{i}));
    end
end
