function test_snrEstimate_noiseWindows()
% Full-pipeline tests for noise window placement strategies and edge cases.
%
% All tests use snrEstimate with real WAV files since noise window
% placement drives getAudioFromFiles via buildNoiseWindow.
%
% Tests:
%   1. noiseDelay gap — 0s vs 0.5s vs 1.0s gap (0.5s is now the default)
%   2. noiseLocation='before' — noise measured only before detection
%   3. noiseLocation='beforeAndAfter' — symmetric (default); must equal params default
%   4. Edge: detection at file start — noise window truncated, should not error
%   5. Edge: detection at file end   — noise window truncated, should not error
%   6. snrType='quantiles' uncalibrated
%   7. snrType='quantiles' calibrated — checks signalBandLevel_dBuPa

fprintf('\n=== test_snrEstimate_noiseWindows ===\n');

signalRMS   = 1.0;
noiseRMS    = 0.1;
toneFreq    = 200;
freq        = [150 250];
durationSec = 4;
tolerance   = 3;   % dB

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1. noiseDelay gap
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- noiseDelay gap ---\n');

[annot, cleanup] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneFreq, 'freq', freq, 'durationSec', durationSec);
try
    snrs = nan(1, 3);
    delays = [0, 0.5, 1.0];
    for k = 1:3
        delay  = delays(k);
        params = struct('snrType', 'spectrogram', 'showClips', false, ...
            'noiseDelay', delay);
        snrs(k) = snrEstimate(annot, params).snr(1);
        assert(isfinite(snrs(k)), ...
            sprintf('noiseDelay=%.1fs: SNR should be finite', delay));
    end
    % Gap should not substantially change the SNR — all windows measure
    % the same background noise, just offset slightly in time
    assert(max(snrs) - min(snrs) < tolerance, ...
        sprintf('noiseDelay 0/0.5/1.0s SNRs differ by %.1f dB (expected < %d)', ...
        max(snrs)-min(snrs), tolerance));
    fprintf('  [PASS] noiseDelay 0/0.5/1.0s: SNR=%.1f / %.1f / %.1f dB\n', snrs(1), snrs(2), snrs(3));
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 2. noiseDuration = 'before'
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- noiseDuration=''before'' ---\n');

[annot, cleanup] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneFreq, 'freq', freq, 'durationSec', durationSec);
try
    params = struct('snrType', 'spectrogram', 'showClips', false, ...
        'noiseLocation', 'before');
    res2 = snrEstimate(annot, params);
    snr = res2.snr(1); rmsS = 10^(res2.signalRMSdB(1)/10); rmsN = 10^(res2.noiseRMSdB(1)/10);
    assert(isfinite(snr), 'before: SNR must be finite');
    assert(rmsS > rmsN,   'before: signal must exceed noise');
    fprintf('  [PASS] noiseDuration=before: SNR=%.1f dB\n', snr);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 3. noiseDuration = 'beforeAndAfter' matches default
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- noiseDuration=''beforeAndAfter'' equals default ---\n');

[annot, cleanup] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneFreq, 'freq', freq, 'durationSec', durationSec);
try
    snrBA = snrEstimate(annot, struct('snrType','spectrogram','showClips',false, ...
        'noiseLocation', 'beforeAndAfter')).snr(1);
    snrDef = snrEstimate(annot, struct('snrType','spectrogram','showClips',false)).snr(1);
    assert(isfinite(snrBA), 'beforeAndAfter: SNR must be finite');
    assert(abs(snrBA - snrDef) < 0.1, ...
        sprintf('beforeAndAfter should equal default: %.2f vs %.2f dB', snrBA, snrDef));
    fprintf('  [PASS] beforeAndAfter=default: SNR=%.1f dB\n', snrBA);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 4. Edge case: detection near file start
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- edge case: detection near file start ---\n');

% createTestFixture has bufferSec=5s. Push t0 4s earlier so the noise
% window is mostly outside the file — tests graceful truncation.
[annot, cleanup] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneFreq, 'freq', freq, 'durationSec', durationSec);
try
    annotEdge      = annot;
    annotEdge.t0   = annot.t0   - 4/86400;
    annotEdge.tEnd = annot.tEnd - 4/86400;

    params = struct('snrType', 'spectrogram', 'showClips', false);
    snr = snrEstimate(annotEdge, params).snr(1);
    % Must not error. SNR may be NaN if noise window is completely outside
    % file, or finite if partially available.
    assert(isnan(snr) || isfinite(snr), ...
        'file-start edge: must return finite or NaN without erroring');
    if isfinite(snr)
        fprintf('  [PASS] near file start: SNR=%.1f dB (partial noise window)\n', snr);
    else
        fprintf('  [PASS] near file start: returned NaN gracefully\n');
    end
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 5. Edge case: detection near file end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- edge case: detection near file end ---\n');

% Push tEnd 4s later so the after-noise window is mostly outside the file.
[annot, cleanup] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneFreq, 'freq', freq, 'durationSec', durationSec);
try
    annotEdge      = annot;
    annotEdge.t0   = annot.t0   + 4/86400;
    annotEdge.tEnd = annot.tEnd + 4/86400;

    params = struct('snrType', 'spectrogram', 'showClips', false);
    snr = snrEstimate(annotEdge, params).snr(1);
    assert(isnan(snr) || isfinite(snr), ...
        'file-end edge: must return finite or NaN without erroring');
    if isfinite(snr)
        fprintf('  [PASS] near file end: SNR=%.1f dB (partial noise window)\n', snr);
    else
        fprintf('  [PASS] near file end: returned NaN gracefully\n');
    end
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 6. snrType = 'quantiles' — uncalibrated
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- snrType=quantiles (uncalibrated) ---\n');

[annot, cleanup] = createTestFixture( ...
    'signalRMS', signalRMS, 'noiseRMS', noiseRMS, ...
    'toneFreqHz', toneFreq, 'freq', freq, 'durationSec', durationSec);
try
    params = struct('snrType', 'quantiles', 'showClips', false);
    resQ = snrEstimate(annot, params);
    snr = resQ.snr(1); rmsS = 10^(resQ.signalRMSdB(1)/10); rmsN = 10^(resQ.noiseRMSdB(1)/10);
    assert(isfinite(snr), 'quantiles uncal: SNR must be finite');
    assert(rmsS > rmsN,   'quantiles uncal: signal must exceed noise');
    fprintf('  [PASS] quantiles uncalibrated: SNR=%.1f dB\n', snr);

    % Noise-only should give SNR near 0 dB
    [annotNoise, cleanupNoise] = createTestFixture( ...
        'signalRMS', 0, 'noiseRMS', noiseRMS, ...
        'freq', freq, 'durationSec', durationSec);
    snrNoise = snrEstimate(annotNoise, params).snr(1);
    % quantiles splits the signal window into high (top 15%) vs low (bottom 85%)
    % cells. For pure noise these will still differ, giving SNR > 0 dB.
    % The key property is that noise-only SNR < high-SNR SNR.
    % For stationary Gaussian noise, spectrogram PSD cells follow an
    % exponential distribution (chi-squared with 2 DOF / 2).
    % The analytical noise-only SNR is:
    %   E[X | X >= Q_0.85] / E[X | X < Q_0.85]
    % By the memoryless property of the exponential:
    %   E[X | X >= Q_p] = Q_p + mu  where Q_p = -mu*ln(1-p)
    %   E[X | X <  Q_p] = integral_0^{Q_p} x*exp(-x) dx / p
    % With p=0.85, mu=1: ratio = 2.8971/0.6652 = 4.355 => 6.39 dB
    expectedNoiseSNRdB = 6.39;   % analytical value for exponential PSD cells
    assert(abs(snrNoise - expectedNoiseSNRdB) < 1.0, ...
        sprintf('quantiles noise-only: SNR=%.2f dB, analytical=%.2f dB (err=%.2f)', ...
        snrNoise, expectedNoiseSNRdB, abs(snrNoise-expectedNoiseSNRdB)));
    fprintf('  [PASS] quantiles noise-only: SNR=%.2f dB (analytical=%.2f dB)\n', ...
        snrNoise, expectedNoiseSNRdB);
    cleanupNoise();
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7. snrType = 'quantiles' — calibrated
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- snrType=quantiles (calibrated) ---\n');

trueSigLevel  = 122;
trueNoiseLvl  = 90;
trueSNRdB     = trueSigLevel - trueNoiseLvl;

[annot, metadata, cleanup] = createCalibratedTestFixture( ...
    'signalLeveldB', trueSigLevel, 'noiseLeveldB', trueNoiseLvl, ...
    'toneFreqHz', 100, 'freq', [80 120], 'durationSec', 4);
try
    % Run as vector to get result table with acoustic level columns
    params = struct('snrType', 'quantiles', 'showClips', false, ...
        'metadata', metadata, 'freq', [80 120]);
    [result] = snrEstimate([annot; annot], params);

    snr = result.snr(1);
    assert(isfinite(snr), 'quantiles cal: SNR must be finite');
    fprintf('  [PASS] quantiles calibrated: SNR=%.1f dB (finite)\n', snr);

    % Calibration scales all PSD cells equally so the within-window quantile
    % ratio (top 15% / bottom 85%) is unchanged — calibrated SNR != acoustic SNR.
    % What calibration DOES do is shift the absolute PSD values.
    % Verify acoustic level columns are present (populated by snrEstimate).
    assert(ismember('signalBandLevel_dBuPa', result.Properties.VariableNames), ...
        'quantiles cal: signalBandLevel_dBuPa column missing');
    sigLevel   = result.signalBandLevel_dBuPa(1);
    noiseLevel = result.noiseBandLevel_dBuPa(1);
    assert(isfinite(sigLevel),   'quantiles cal: signalBandLevel_dBuPa must be finite');
    assert(isfinite(noiseLevel), 'quantiles cal: noiseBandLevel_dBuPa must be finite');
    assert(sigLevel > noiseLevel, ...
        sprintf('quantiles cal: signal (%.1f) should exceed noise (%.1f) in dBuPa', ...
        sigLevel, noiseLevel));
    fprintf('  [PASS] quantiles cal: acoustic columns present, signal=%.1f > noise=%.1f dBuPa\n', ...
        sigLevel, noiseLevel);
catch err; cleanup(); rethrow(err); end
cleanup();

fprintf('\n=== test_snrEstimate_noiseWindows PASSED ===\n');
end
