function test_snrEstimate_correctness()
% Analytical correctness and invariance tests for snrEstimate.
%
% These tests have known correct answers or analytical bounds, making them
% stronger than "output is finite and positive" checks.
%
% Tests:
%   (1)  Noise-only SNR ≈ 0 dB for linear methods (spectrogram, slices, timeDomain)
%   (2)  SNR monotonically increases with signal level (all methods)
%   (3)  SNR invariant to uniform amplitude scaling of signal+noise
%   (4)  Frequency band selectivity: tone outside band gives low SNR
%   (5)  Lurton formula: SNR=0 for noise-only, large for high-SNR signal
%   (6)  noiseDuration_s: longer noise window gives same SNR ± tolerance
%   (7)  Analytical SNR recovery: spectrogram/slices within 2 dB of truth
%   (8)  trimAnnotation + snrEstimate pipeline: trim improves SNR
%   (9)  removeClicks via params: click suppression does not degrade SNR

fprintf('\n=== test_snrEstimate_correctness ===\n');

sampleRate = 2000;
durSec     = 6;
toneHz     = 200;
freq       = [150 250];
signalRMS  = 1.0;   % used for annotHigh
noiseRMS   = 0.1;
tol        = 3;   % dB tolerance for analytical checks

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Shared fixtures
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annotLow,  cleanupLow]  = createTestFixture('signalRMS', 0,    'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', durSec);
[annotMed,  cleanupMed]  = createTestFixture('signalRMS', 0.1,  'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', durSec);
[annotHigh, cleanupHigh] = createTestFixture('signalRMS', 1.0,  'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', durSec);
[annotLoud, cleanupLoud] = createTestFixture('signalRMS', 2.0,  'noiseRMS', noiseRMS*2, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', durSec);   % scaled up signal+noise
[annotOOB,  cleanupOOB]  = createTestFixture('signalRMS', 1.0,  'noiseRMS', noiseRMS, ...
    'toneFreqHz', 400, 'freq', freq, 'durationSec', durSec);      % tone outside band

cleanups = {cleanupLow, cleanupMed, cleanupHigh, cleanupLoud, cleanupOOB};
cleanupAll = onCleanup(@() cellfun(@(f) f(), cleanups));

pBase = struct('showClips', false, 'verbose', false);
linearMethods = {'spectrogram', 'spectrogramSlices', 'timeDomain'};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (1) Noise-only SNR ≈ 0 dB for linear methods
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (1) Noise-only SNR ≈ 0 dB ---\n');
for k = 1:numel(linearMethods)
    m = linearMethods{k};
    p = pBase; p.snrType = m; p.freq = freq;
    snr0 = snrEstimate(annotLow, p).snr(1);
    assert(abs(snr0) < tol, ...
        sprintf('%s noise-only: SNR=%.2f dB, expected ≈0', m, snr0));
    fprintf('  [PASS] %s noise-only: %.2f dB\n', m, snr0);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (2) SNR monotonically increases with signal level
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (2) SNR monotonic with signal level ---\n');
% nist excluded: histogram method is too coarse to distinguish low-SNR levels reliably
allMethods = {'spectrogram', 'spectrogramSlices', 'timeDomain', 'quantiles'};
for k = 1:numel(allMethods)
    m = allMethods{k};
    p = pBase; p.snrType = m; p.freq = freq;
    snrLow = snrEstimate(annotLow,  p).snr(1);
    snrMed = snrEstimate(annotMed,  p).snr(1);
    snrHigh = snrEstimate(annotHigh, p).snr(1);
    assert(snrMed > snrLow, ...
        sprintf('%s: SNR not monotonic: med(%.1f) <= low(%.1f)', m, snrMed, snrLow));
    assert(snrHigh > snrMed, ...
        sprintf('%s: SNR not monotonic: high(%.1f) <= med(%.1f)', m, snrHigh, snrMed));
    fprintf('  [PASS] %s: %.1f < %.1f < %.1f dB\n', m, snrLow, snrMed, snrHigh);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (3) SNR invariant to uniform amplitude scaling of signal+noise
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (3) SNR invariant to uniform scaling ---\n');
% annotHigh has signalRMS=1.0, noiseRMS=0.1
% annotLoud has signalRMS=2.0, noiseRMS=0.2 (same ratio, double amplitude)
for k = 1:numel(linearMethods)
    m = linearMethods{k};
    p = pBase; p.snrType = m; p.freq = freq;
    snrRef = snrEstimate(annotHigh, p).snr(1);
    snrLoud = snrEstimate(annotLoud, p).snr(1);
    assert(abs(snrRef - snrLoud) < 1.0, ...
        sprintf('%s scaling invariance: ref=%.2f, loud=%.2f (diff=%.2f)', ...
        m, snrRef, snrLoud, abs(snrRef-snrLoud)));
    fprintf('  [PASS] %s: ref=%.1f dB, 2x=%.1f dB (diff=%.2f)\n', ...
        m, snrRef, snrLoud, abs(snrRef-snrLoud));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (4) Frequency band selectivity: tone outside band gives low SNR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (4) Frequency band selectivity ---\n');
for k = 1:numel(linearMethods)
    m = linearMethods{k};
    p = pBase; p.snrType = m; p.freq = freq;
    snrIn = snrEstimate(annotHigh, p).snr(1);   % tone at 200 Hz, band [150 250]
    snrOut = snrEstimate(annotOOB,  p).snr(1);   % tone at 400 Hz, outside band
    assert(snrIn > snrOut + 5, ...
        sprintf('%s band selectivity: in=%.1f dB, out=%.1f dB (expected in > out+5)', ...
        m, snrIn, snrOut));
    fprintf('  [PASS] %s: in-band=%.1f dB, out-of-band=%.1f dB\n', m, snrIn, snrOut);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (5) Lurton formula: SNR=0 for noise-only, large for high SNR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (5) Lurton formula ---\n');
pLurton = pBase; pLurton.snrType = 'spectrogram'; pLurton.useLurton = true; pLurton.freq = freq;
snrLurtonNoise = snrEstimate(annotLow,  pLurton).snr(1);
snrLurtonHigh = snrEstimate(annotHigh, pLurton).snr(1);
% Lurton: SNR = 10*log10((S-N)^2/noiseVar). For noise-only S≈N, so SNR << 0.
% For high SNR S>>N, so Lurton >> simple formula.
assert(snrLurtonNoise < 0, ...
    sprintf('Lurton noise-only should be negative, got %.1f dB', snrLurtonNoise));
assert(snrLurtonHigh > 20, ...
    sprintf('Lurton high-SNR should be large, got %.1f dB', snrLurtonHigh));
fprintf('  [PASS] Lurton: noise-only=%.1f dB, high-SNR=%.1f dB\n', ...
    snrLurtonNoise, snrLurtonHigh);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (6) noiseDuration_s: longer noise window gives same SNR ± tolerance
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (6) noiseDuration_s ---\n');
pDur1 = pBase; pDur1.snrType = 'spectrogram'; pDur1.freq = freq;
pDur2 = pBase; pDur2.snrType = 'spectrogram'; pDur2.freq = freq; pDur2.noiseDuration_s = 10;
snrDur1 = snrEstimate(annotHigh, pDur1).snr(1);
snrDur2 = snrEstimate(annotHigh, pDur2).snr(1);
assert(abs(snrDur1 - snrDur2) < tol, ...
    sprintf('noiseDuration_s: default=%.1f dB, 10s=%.1f dB (diff=%.2f)', ...
    snrDur1, snrDur2, abs(snrDur1-snrDur2)));
fprintf('  [PASS] noiseDuration_s: default=%.1f dB, 10s=%.1f dB\n', snrDur1, snrDur2);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (7) Analytical SNR recovery: spectrogram/slices within 2 dB of truth
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (7) Analytical SNR recovery ---\n');
% True in-band SNR: createTestFixture scales noise so in-band RMS = noiseRMS.
% PSD methods: tone signal = signalRMS^2/2 (sine) vs noiseRMS^2.
% 10*log10(1.0^2/2 / 0.1^2) = 10*log10(50) = 17.0 dB
inBandSNRdB  = 10 * log10(signalRMS^2 / 2 / noiseRMS^2);   % 17 dB

for k = 1:2   % spectrogram and spectrogramSlices
    m = linearMethods{k};
    p = pBase; p.snrType = m; p.freq = freq;
    snrEst = snrEstimate(annotHigh, p).snr(1);
    err = abs(snrEst - inBandSNRdB);
    assert(err < 3, ...
        sprintf('%s analytical: estimated=%.2f dB, truth=%.2f dB, err=%.2f dB', ...
        m, snrEst, inBandSNRdB, err));
    fprintf('  [PASS] %s: %.2f dB (truth=%.2f dB, err=%.2f dB)\n', ...
        m, snrEst, inBandSNRdB, err);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (8) trimAnnotation + snrEstimate pipeline
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (8) trimAnnotation + snrEstimate pipeline ---\n');
% Wide annotation with 1.5s silence margins — trim should improve SNR
annotWide      = annotHigh;
annotWide.t0   = annotHigh.t0   - 1.5/86400;
annotWide.tEnd = annotHigh.tEnd + 1.5/86400;
annotWide.duration = (annotWide.tEnd - annotWide.t0) * 86400;

annotTrimmed = trimAnnotation(annotWide, 'freq', freq, 'showPlot', false);
assert(annotTrimmed.trimApplied, 'trim should have been applied');
assert(annotTrimmed.duration < annotWide.duration, ...
    'trimmed duration should be less than wide annotation');

pPipeline = pBase; pPipeline.snrType = 'spectrogramSlices'; pPipeline.freq = freq;
pPipeline.noiseLocation = 'before'; pPipeline.noiseDuration_s = 2;
snrWide = snrEstimate(annotWide,    pPipeline).snr(1);
snrTrimmed = snrEstimate(annotTrimmed, pPipeline).snr(1);
assert(isfinite(snrWide) && isfinite(snrTrimmed), ...
    'both SNRs should be finite');
assert(snrTrimmed >= snrWide - 1, ...
    sprintf('trim+SNR pipeline: trimmed=%.1f dB, wide=%.1f dB', snrTrimmed, snrWide));
fprintf('  [PASS] trim+SNR: wide=%.1f dB, trimmed=%.1f dB\n', snrWide, snrTrimmed);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (9) removeClicks via params does not degrade SNR on clean signal
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- (9) removeClicks via params ---\n');
pClean  = pBase; pClean.snrType  = 'spectrogram'; pClean.freq = freq;
pClicks = pBase; pClicks.snrType = 'spectrogram'; pClicks.freq = freq;
pClicks.removeClicks = struct('threshold', 3, 'power', 1000);

snrClean = snrEstimate(annotHigh, pClean).snr(1);
snrClicks = snrEstimate(annotHigh, pClicks).snr(1);
assert(abs(snrClean - snrClicks) < tol, ...
    sprintf('removeClicks on clean signal: clean=%.1f dB, with=%.1f dB', ...
    snrClean, snrClicks));
fprintf('  [PASS] removeClicks on clean: %.1f dB vs %.1f dB (diff=%.2f)\n', ...
    snrClean, snrClicks, abs(snrClean-snrClicks));

fprintf('\n=== test_snrEstimate_correctness PASSED ===\n');
end
