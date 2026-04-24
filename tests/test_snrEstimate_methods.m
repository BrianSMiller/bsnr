function test_snrEstimate_methods()
% Full-stack tests for all SNR methods via snrEstimate.
%
% All tests call snrEstimate() with snrType=<method> — no direct calls to
% internal method functions. This tests the complete pipeline including
% audio loading, noise window construction, and output formatting.
%
% Analytical references:
%   createTestFixture scales noise so IN-BAND RMS = noiseRMS.
%   For a pure tone, PSD methods measure signal as signalRMS^2/2 (sine factor).
%   inBandSNRdB_psd = 10*log10(signalRMS^2/2 / noiseRMS^2)
%                   = 10*log10(0.5/0.01) = 17 dB
%   timeDomain (bandpass FIR): same ~17 dB (mean(sin^2)=0.5 cancels).
%   ridge/synchrosqueeze: per-bin geometry, SNR > inBandSNRdB_psd.
%
% Tests per method:
%   (a) High-SNR tone: SNR > 0, within tolerance of analytical value
%   (b) Noise-only: SNR near 0 (or negative) — no false detections
%   (c) Signal > noise-only SNR by meaningful margin

fprintf('\n=== test_snrEstimate_methods ===\n');

sampleRate = 2000;
durSec     = 8;
toneHz     = 200;
signalRMS  = 1.0;
noiseRMS   = 0.1;
freq       = [150 250];

% Analytical in-band SNR (createTestFixture scales noise to in-band RMS = noiseRMS)
% PSD methods: tone signal power = signalRMS^2/2 (sine factor)
inBandSNRdB_psd = 10 * log10(signalRMS^2/2 / noiseRMS^2);   % 17 dB

% Build fixtures
[annotHigh, cleanupHigh] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', durSec);
[annotNoise, cleanupNoise] = createTestFixture( ...
    'signalRMS', 0, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', durSec);

% For histogram: needs longer audio
[annotLong, cleanupLong] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', 30);
[annotLongNoise, cleanupLongNoise] = createTestFixture( ...
    'signalRMS', 0, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneHz, 'freq', freq, 'durationSec', 30);

cleanupAll = onCleanup(@() cellfun(@(f) f(), ...
    {cleanupHigh, cleanupNoise, cleanupLong, cleanupLongNoise}));

pBase = struct('showClips', false, 'verbose', false, 'freq', freq);

fprintf('Analytical in-band SNR (PSD): %.1f dB\n\n', inBandSNRdB_psd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% spectrogram
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- spectrogram ---\n');
p = pBase; p.snrType = 'spectrogram';
snrHigh  = snrEstimate(annotHigh,  p);
snrNoise = snrEstimate(annotNoise, p);
assert(isfinite(snrHigh),  'spectrogram: high-SNR should be finite');
assert(isfinite(snrNoise), 'spectrogram: noise-only should be finite');
assert(snrHigh > snrNoise + 10, ...
    sprintf('spectrogram: high (%.1f) should exceed noise (%.1f) by >10 dB', snrHigh, snrNoise));
assert(abs(snrHigh - inBandSNRdB_psd) < 3, ...
    sprintf('spectrogram: %.1f dB, expected %.1f dB (±3)', snrHigh, inBandSNRdB_psd));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB (truth=%.1f dB)\n', snrHigh, snrNoise, inBandSNRdB_psd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% spectrogramSlices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- spectrogramSlices ---\n');
p = pBase; p.snrType = 'spectrogramSlices';
snrHigh  = snrEstimate(annotHigh,  p);
snrNoise = snrEstimate(annotNoise, p);
assert(isfinite(snrHigh) && isfinite(snrNoise), 'spectrogramSlices: must be finite');
assert(snrHigh > snrNoise + 10, ...
    sprintf('spectrogramSlices: high (%.1f) should exceed noise (%.1f) by >10 dB', snrHigh, snrNoise));
assert(abs(snrHigh - inBandSNRdB_psd) < 3, ...
    sprintf('spectrogramSlices: %.1f dB, expected %.1f dB (±3)', snrHigh, inBandSNRdB_psd));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB (truth=%.1f dB)\n', snrHigh, snrNoise, inBandSNRdB_psd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% timeDomain
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- timeDomain ---\n');
p = pBase; p.snrType = 'timeDomain';
snrHigh  = snrEstimate(annotHigh,  p);
snrNoise = snrEstimate(annotNoise, p);
% timeDomain: bandpass FIR, same in-band SNR reference as PSD methods
assert(isfinite(snrHigh) && isfinite(snrNoise), 'timeDomain: must be finite');
assert(snrHigh > snrNoise + 10, ...
    sprintf('timeDomain: high (%.1f) should exceed noise (%.1f) by >10 dB', snrHigh, snrNoise));
assert(abs(snrHigh - inBandSNRdB_psd) < 5, ...
    sprintf('timeDomain: %.1f dB, expected %.1f dB (±5)', snrHigh, inBandSNRdB_psd));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB (truth=%.1f dB)\n', snrHigh, snrNoise, inBandSNRdB_psd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ridge
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- ridge ---\n');
p = pBase; p.snrType = 'ridge';
snrHigh  = snrEstimate(annotHigh,  p);
snrNoise = snrEstimate(annotNoise, p);
% Ridge: per-bin geometry, nBandBins = bw/(Nyquist/nfft)
assert(isfinite(snrHigh) && isfinite(snrNoise), 'ridge: must be finite');
assert(snrHigh > snrNoise + 10, ...
    sprintf('ridge: high (%.1f) should exceed noise (%.1f) by >10 dB', snrHigh, snrNoise));
assert(snrHigh > inBandSNRdB_psd, ...
    sprintf('ridge: %.1f dB should exceed in-band SNR %.1f dB (per-bin geometry)', ...
    snrHigh, inBandSNRdB_psd));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB\n', snrHigh, snrNoise);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% synchrosqueeze
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- synchrosqueeze ---\n');
p = pBase; p.snrType = 'synchrosqueeze';
snrHigh  = snrEstimate(annotHigh,  p);
snrNoise = snrEstimate(annotNoise, p);
assert(isfinite(snrHigh) && isfinite(snrNoise), 'synchrosqueeze: must be finite');
assert(snrHigh > snrNoise + 10, ...
    sprintf('synchrosqueeze: high (%.1f) should exceed noise (%.1f) by >10 dB', snrHigh, snrNoise));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB\n', snrHigh, snrNoise);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% quantiles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- quantiles ---\n');
p = pBase; p.snrType = 'quantiles';
snrHigh  = snrEstimate(annotHigh,  p);
snrNoise = snrEstimate(annotNoise, p);
assert(isfinite(snrHigh) && isfinite(snrNoise), 'quantiles: must be finite');
assert(snrHigh > snrNoise, ...
    sprintf('quantiles: high (%.1f) should exceed noise (%.1f)', snrHigh, snrNoise));
% Quantiles noise-only analytical value ≈ 6.39 dB (exponential PSD cells)
assert(abs(snrNoise - 6.39) < 1.5, ...
    sprintf('quantiles noise-only: %.2f dB, analytical=6.39 dB (±1.5)', snrNoise));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB (analytical noise≈6.39 dB)\n', snrHigh, snrNoise);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% nist (histogram)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- nist (histogram) ---\n');
p = pBase; p.snrType = 'nist';
snrHigh  = snrEstimate(annotLong,       p);
snrNoise = snrEstimate(annotLongNoise,  p);
assert(isfinite(snrHigh) && isfinite(snrNoise), 'nist: must be finite');
assert(snrHigh > snrNoise + 5, ...
    sprintf('nist: high (%.1f) should exceed noise (%.1f) by >5 dB', snrHigh, snrNoise));
assert(abs(snrHigh - inBandSNRdB_psd) < 6, ...
    sprintf('nist: %.1f dB, expected %.1f dB (±6)', snrHigh, inBandSNRdB_psd));
fprintf('  [PASS] high=%.1f dB, noise=%.1f dB (truth=%.1f dB)\n', snrHigh, snrNoise, inBandSNRdB_psd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SRW upcall: ridge and synchrosqueeze track FM sweep
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- ridge + synchrosqueeze: SRW FM upcall ---\n');

srwRate = 1000;
srwFreq = [75 210];
bufSec  = 2;

[srwSig, ~] = makeSRWUpcall(srwRate, 0.1);
rng(7);
srwWideRMS = 0.1 * sqrt(srwRate/2 / diff(srwFreq));
bufSamps   = round(bufSec * srwRate);
fullAudio  = [srwWideRMS*randn(bufSamps,1); srwSig; srwWideRMS*randn(bufSamps,1)];
fullAudio  = fullAudio * (0.9/max(abs(fullAudio)));

srwDir  = tempname(); mkdir(srwDir);
srwT0   = floor(now()*86400)/86400;
audiowrite(fullfile(srwDir, [datestr(srwT0,'yyyy-mm-dd_HH-MM-SS') '.wav']), fullAudio, srwRate);
cleanupSRW = onCleanup(@() rmdir(srwDir,'s'));

srwAnnot.soundFolder = srwDir;
srwAnnot.t0          = srwT0 + bufSec/86400;
srwAnnot.tEnd        = srwT0 + (bufSec+1.0)/86400;
srwAnnot.duration    = 1.0;
srwAnnot.freq        = srwFreq;
srwAnnot.channel     = 1;

for m = {'ridge', 'synchrosqueeze'}
    p = struct('snrType', m{1}, 'showClips', false, 'verbose', false);
    snrSRW = snrEstimate(srwAnnot, p);
    assert(isfinite(snrSRW) && snrSRW > 5, ...
        sprintf('%s SRW upcall: SNR=%.1f dB, expected >5 dB', m{1}, snrSRW));
    fprintf('  [PASS] %s SRW upcall: %.1f dB\n', m{1}, snrSRW);
end

fprintf('\n=== test_snrEstimate_methods PASSED ===\n');
end
