function test_removeClicks()
% Unit tests for removeClicks and its integration with SNR estimation.
%
% Tests verify:
%   (1) removeClicks suppresses high-amplitude click samples
%   (2) Clicks inflate rmsSignal — contaminated SNR is significantly higher
%       than the true SNR
%   (3) After removeClicks, SNR estimate recovers towards the true value
%   (4) removeClicks does not significantly distort a click-free signal
%   (5) removeClicks is robust to all-zero input
%
% removeClicks algorithm (PAMGuard style):
%   thresh  = threshold * std(audio)
%   weights = 1 / (1 + ((x - mean) / thresh)^power)
%   output  = weights .* audio
%
% With power=1000 this is effectively a hard gate: samples beyond
% threshold*std are driven to near zero.

fprintf('\n=== test_removeClicks ===\n');

sampleRate       = 2000;
durationSec      = 10;
toneFreqHz       = 200;
signalRMS        = 1.0;
noiseRMS         = 0.1;
freq             = [150 250];
clickInterval    = 1.0;    % s between clicks
clickAmplitude   = 50.0;   % >> 3 * std(audio) ≈ 3 * noiseRMS = 0.3; high enough for >3 dB SNR inflation

nSlices  = 30;
overlap  = 0.75;
nfft     = 2^nextpow2(floor(durationSec / nSlices / overlap * sampleRate));
nOverlap = floor(nfft * overlap);

threshold = 3;
power     = 1000;

[sigWithClicks, sigClean, noiseAudio, clickSamples] = makeClickAudio( ...
    sampleRate, durationSec, toneFreqHz, signalRMS, noiseRMS, ...
    clickInterval, clickAmplitude);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (1) removeClicks suppresses clicks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- removeClicks basic suppression ---\n');

cleaned = removeClicks(sigWithClicks, threshold, power);

% Check that peak amplitude is dramatically reduced after cleaning
peakBefore = max(abs(sigWithClicks));
peakAfter  = max(abs(cleaned));
assert(peakAfter < peakBefore / 5, ...
    sprintf('removeClicks: peak should be reduced by >14 dB, got %.1f -> %.1f', ...
    peakBefore, peakAfter));
fprintf('  [PASS] peak reduced from %.2f to %.3f (%.1f dB reduction)\n', ...
    peakBefore, peakAfter, 20*log10(peakBefore/peakAfter));

% Verify click bursts are suppressed — use full burst window not just start index
% (start index may land on a zero crossing of the sine burst)
clickDurSamples = max(2, round(0.005 * sampleRate));
clickPowerBefore = 0; clickPowerAfter = 0; nClickSamples = 0;
for k = 1:numel(clickSamples)
    idx = clickSamples(k) : min(length(sigWithClicks), clickSamples(k) + clickDurSamples - 1);
    clickPowerBefore = clickPowerBefore + sum(sigWithClicks(idx).^2);
    clickPowerAfter  = clickPowerAfter  + sum(cleaned(idx).^2);
    nClickSamples = nClickSamples + numel(idx);
end
clickPowerBefore = clickPowerBefore / nClickSamples;
clickPowerAfter  = clickPowerAfter  / nClickSamples;
assert(clickPowerAfter < clickPowerBefore / 100, ...
    sprintf('removeClicks: click burst power should be reduced by >20 dB, got %.1f dB', ...
    10*log10(clickPowerBefore / max(clickPowerAfter, 1e-30))));
fprintf('  [PASS] click burst power reduced by %.1f dB\n', ...
    10*log10(clickPowerBefore / max(clickPowerAfter, 1e-30)));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (2) Clicks inflate SNR estimate
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- SNR inflation by clicks ---\n');

trueSNRdB = 10 * log10(signalRMS^2 / noiseRMS^2);

% Use snrTimeDomain (mean instantaneous power) rather than snrSpectrogram
% (mean PSD). Short clicks at 1 ms / 1 s interval occupy ~0.1%% of signal
% duration — their effect on mean PSD is negligible but their effect on
% mean instantaneous power is large (amplitude 10 vs RMS ~1).
[rmsS_clean,  rmsN_clean,  ~] = snrTimeDomain( ...
    sigClean,      noiseAudio, freq, sampleRate);
[rmsS_clicks, rmsN_clicks, ~] = snrTimeDomain( ...
    sigWithClicks, noiseAudio, freq, sampleRate);

snr_clean  = 10 * log10(rmsS_clean  / rmsN_clean);
snr_clicks = 10 * log10(rmsS_clicks / rmsN_clicks);

assert(snr_clicks > snr_clean + 3, ...
    sprintf('Clicks should inflate SNR by >3 dB: clean=%.1f, with clicks=%.1f', ...
    snr_clean, snr_clicks));
fprintf('  [PASS] clicks inflate SNR: clean=%.1f dB, with clicks=%.1f dB (inflation=%.1f dB)\n', ...
    snr_clean, snr_clicks, snr_clicks - snr_clean);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (3) removeClicks recovers SNR toward true value
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- SNR recovery after removeClicks ---\n');

sigCleaned = removeClicks(sigWithClicks, threshold, power);

[rmsS_recovered, rmsN_recovered, ~] = snrTimeDomain( ...
    sigCleaned, noiseAudio, freq, sampleRate);
snr_recovered = 10 * log10(rmsS_recovered / rmsN_recovered);

% Recovered SNR should be closer to true than the contaminated SNR
errBefore = abs(snr_clicks   - snr_clean);
errAfter  = abs(snr_recovered - snr_clean);
assert(errAfter < errBefore, ...
    sprintf('removeClicks should bring SNR closer to clean: before=%.1f dB error, after=%.1f dB error', ...
    errBefore, errAfter));
fprintf('  [PASS] SNR error reduced: %.1f -> %.1f dB (recovered SNR=%.1f dB, clean=%.1f dB)\n', ...
    errBefore, errAfter, snr_recovered, snr_clean);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (4) removeClicks does not significantly distort a clean signal
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- removeClicks does not distort clean signal ---\n');

sigCleanedTwice = removeClicks(sigClean, threshold, power);

[rmsS_orig,    ~, ~] = snrTimeDomain(sigClean,        noiseAudio, freq, sampleRate);
[rmsS_cleaned, ~, ~] = snrTimeDomain(sigCleanedTwice, noiseAudio, freq, sampleRate);

distortionDB = abs(10 * log10(rmsS_cleaned / rmsS_orig));
assert(distortionDB < 1, ...
    sprintf('removeClicks should not distort clean signal: %.2f dB change', distortionDB));
fprintf('  [PASS] clean signal undistorted: %.2f dB change after removeClicks\n', distortionDB);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (5) Robustness: all-zero input
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- removeClicks robustness ---\n');

zeroOut = removeClicks(zeros(100, 1), threshold, power);
assert(all(zeroOut == 0), 'removeClicks: all-zero input should return all-zero output');
fprintf('  [PASS] all-zero input handled correctly\n');

fprintf('\n=== test_removeClicks PASSED ===\n');
end
