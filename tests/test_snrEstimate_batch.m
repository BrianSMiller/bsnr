function test_snrEstimate_batch(runParallel)
% Integration tests for snrEstimate() with vector annotation input.
%
% Tests the serial path (n < parallelThreshold) and optionally the
% parallel path (n >= parallelThreshold). A single long WAV file is
% written containing sequential tone bursts, and annotation windows
% are sliced from it.
%
% INPUT
%   runParallel   logical — if true, also runs the parallel path test

if nargin < 1, runParallel = false; end

fprintf('\n=== test_snrEstimate_batch ===\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Build shared fixture: one long WAV with N sequential tone bursts
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sampleRate  = 2000;
toneHz      = 200;
signalRMS   = 1.0;
noiseRMS    = 0.1;
freq        = [150 250];
detDuration = 2;     % seconds per detection
gapSec      = 2;     % gap between detections (used as noise window)
nAnnotations = 110;  % enough for both serial (5) and parallel (110) tests

totalSec = gapSec + nAnnotations * (detDuration + gapSec);
nTotal   = round(totalSec * sampleRate);

rng(42);
audio = noiseRMS * randn(nTotal, 1);

fileStartDatenum = datenum('2024-01-01 00:00:00', 'yyyy-mm-dd HH:MM:SS');
detStartSecs     = zeros(nAnnotations, 1);

for i = 1:nAnnotations
    onsetSec = gapSec + (i-1) * (detDuration + gapSec);
    iStart   = round(onsetSec * sampleRate) + 1;
    iEnd     = round((onsetSec + detDuration) * sampleRate);
    tTone    = (0 : iEnd-iStart)' / sampleRate;
    audio(iStart:iEnd) = audio(iStart:iEnd) + ...
        signalRMS * sin(2 * pi * toneHz * tTone);
    detStartSecs(i) = onsetSec;
end

% Scale to avoid audiowrite clipping
audio = audio * (0.9 / max(abs(audio)));

tmpDir  = fullfile(tempdir, sprintf('annotSNR_batch_%s', ...
    datestr(now, 'yyyymmdd_HHMMSS_FFF')));
mkdir(tmpDir);
% Use yyyy-mm-dd_HH-MM-SS format — unambiguous in guessFileNameTimestamp
wavPath = fullfile(tmpDir, '2024-01-01_00-00-00.wav');
audiowrite(wavPath, audio, sampleRate);
cleanup = @() rmdir(tmpDir, 's');

% Build annotation struct array
annotArray(nAnnotations) = struct();
for i = 1:nAnnotations
    annotArray(i).soundFolder = tmpDir;
    annotArray(i).t0          = fileStartDatenum + detStartSecs(i)              / 86400;
    annotArray(i).tEnd        = fileStartDatenum + (detStartSecs(i)+detDuration) / 86400;
    annotArray(i).duration    = detDuration;
    annotArray(i).freq        = freq;
    annotArray(i).channel     = 1;
end

try

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (1) Serial path: n < parallelThreshold returns a correctly shaped table
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

nSerial = 5;
params  = struct('snrType', 'spectrogram', 'showClips', false, ...
                 'parallelThreshold', 100);

result = snrEstimate(annotArray(1:nSerial), params);

assert(istable(result), ...
    'serial: output should be a table');
assert(height(result) == nSerial, ...
    sprintf('serial: expected %d rows, got %d', nSerial, height(result)));
assert(all(ismember({'snr','signalRMSdB','noiseRMSdB','noiseVar'}, ...
    result.Properties.VariableNames)), ...
    'serial: table missing expected column names');
assert(~all(isnan(result.snr)), ...
    'serial: all SNR values are NaN — check fixture or noise window');
assert(mean(result.snr, 'omitnan') > 0, ...
    sprintf('serial: mean SNR should be positive, got %.2f dB', ...
    mean(result.snr, 'omitnan')));
fprintf('  [PASS] serial: %d rows, mean SNR = %.2f dB\n', ...
    height(result), mean(result.snr, 'omitnan'));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (2) Parallel path (optional)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if runParallel
    fprintf('  Running parallel test (%d annotations)...\n', nAnnotations);

    params.parallelThreshold = 100;
    result = snrEstimate(annotArray, params);

    assert(istable(result), ...
        'parallel: output should be a table');
    assert(height(result) == nAnnotations, ...
        sprintf('parallel: expected %d rows, got %d', nAnnotations, height(result)));
    assert(sum(isfinite(result.snr)) > nAnnotations * 0.9, ...
        'parallel: >90%% of SNR values should be finite for valid signals');
    assert(mean(result.snr, 'omitnan') > 0, ...
        'parallel: mean SNR should be positive');
    fprintf('  [PASS] parallel: %d rows, mean SNR = %.2f dB\n', ...
        height(result), mean(result.snr, 'omitnan'));

    % Serial and parallel should agree for the same annotations
    serialResult   = snrEstimate(annotArray(1:nSerial), params);
    parallelSubset = result(1:nSerial, :);
    snrDiff = abs(serialResult.snr - parallelSubset.snr);
    assert(all(snrDiff < 0.1 | isnan(snrDiff)), ...
        'parallel vs serial: SNR values should agree within 0.1 dB');
    fprintf('  [PASS] parallel and serial agree within 0.1 dB\n');
else
    fprintf('  [SKIP] parallel test (runParallel=false)\n');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (3) Mixed valid/invalid annotations: invalid row returns NaN, others finite
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mixedAnnot        = annotArray(1:5);
mixedAnnot(3).t0  = datenum('2099-01-01', 'yyyy-mm-dd');
mixedAnnot(3).tEnd = mixedAnnot(3).t0 + detDuration / 86400;

params.parallelThreshold = 100;
result = snrEstimate(mixedAnnot, params);

assert(istable(result), ...
    'mixed: output should be a table');
assert(isnan(result.snr(3)), ...
    'mixed: out-of-range annotation should produce NaN');
assert(sum(isfinite(result.snr)) >= 3, ...
    'mixed: valid annotations should still produce finite SNR');
fprintf('  [PASS] mixed valid/invalid: row 3 = NaN, others finite\n');

catch err
    cleanup();
    rethrow(err);
end

cleanup();
fprintf('\n=== test_snrEstimate_batch PASSED ===\n');
end
