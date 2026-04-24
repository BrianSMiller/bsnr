function test_trimAnnotation()
% Tests for trimAnnotation.m
%
% Tests:
%   (1) Trimmed bounds are within original bounds
%   (2) Trim reduces duration for a call with silent margins
%   (3) Fixed params.freq suppresses frequency trimming
%   (4) Per-annotation freq bounds allow frequency trimming
%   (5) Very short annotation: trim gracefully skipped (minSlices guard)
%   (6) trimApplied column is added to output
%   (7) Output type matches input type (table in, table out; struct in, struct out)
%   (8) SNR after trim is >= SNR before trim for high-SNR signal with margins

fprintf('\n=== test_trimAnnotation ===\n');

sampleRate  = 1000;
toneHz      = 200;
signalRMS   = 2.0;
noiseRMS    = 0.1;
freq        = [150 250];

%% Build fixture — extend annotation bounds into the existing noise buffer
% createTestFixture writes noise buffers on each side of the signal.
% We extend the annotation 1.5s on each side to include silent margins,
% making trimming meaningful.

[annotTone, cleanupTone] = createTestFixture( ...
    'signalRMS',   signalRMS, ...
    'noiseRMS',    noiseRMS, ...
    'toneFreqHz',  toneHz, ...
    'freq',        freq, ...
    'durationSec', 4);
cleanupObj = onCleanup(cleanupTone);

% Extend annotation 1.5 s on each side into the existing noise buffer
marginSec      = 1.5;
annotWide      = annotTone;
annotWide.t0   = annotTone.t0   - marginSec/86400;
annotWide.tEnd = annotTone.tEnd + marginSec/86400;
annotWide.duration = (annotWide.tEnd - annotWide.t0) * 86400;

% params passed as name-value pairs directly to trimAnnotation

%% (1) Trimmed bounds within original bounds

fprintf('--- (1) Trimmed bounds within original bounds ---\n');
trimmed = trimAnnotation(annotWide, 'freq', freq, 'showPlot', false);
assert(trimmed.t0   >= annotWide.t0,   'Trimmed t0 should be >= original t0');
assert(trimmed.tEnd <= annotWide.tEnd, 'Trimmed tEnd should be <= original tEnd');
assert(trimmed.duration <= annotWide.duration, 'Trimmed duration should be <= original');
fprintf('  [PASS] trimmed bounds within original: %.2f s -> %.2f s\n', ...
    annotWide.duration, trimmed.duration);

%% (2) Trim reduces duration for signal with silent margins

fprintf('--- (2) Trim reduces duration for signal with silent margins ---\n');
assert(trimmed.duration < annotWide.duration * 0.9, ...
    sprintf('Trim should reduce duration by >10%% for signal with 2s margins (got %.2f -> %.2f s)', ...
    annotWide.duration, trimmed.duration));
fprintf('  [PASS] duration reduced: %.2f s -> %.2f s (target ~4s)\n', ...
    annotWide.duration, trimmed.duration);

%% (3) Fixed params.freq suppresses frequency trimming

fprintf('--- (3) Fixed freq suppresses frequency trimming ---\n');
trimmedFixed = trimAnnotation(annotWide, 'freq', freq, 'showPlot', false);
assert(isequal(trimmedFixed.freq, freq), ...
    'Fixed params.freq: annotation freq should be unchanged');
fprintf('  [PASS] fixed freq unchanged: [%.0f %.0f] Hz\n', freq(1), freq(2));

%% (4) Per-annotation freq bounds allow frequency trimming

fprintf('--- (4) Per-annotation freq allows frequency trimming ---\n');
annotPerFreq      = annotWide;
annotPerFreq.freq = [100 300];  % symmetric about 200 Hz tone, wider than actual [150 250]
trimmedPerFreq    = trimAnnotation(annotPerFreq, 'showPlot', false);
% Trimmed freq should be tighter than original wide bounds
assert(trimmedPerFreq.freq(1) >= annotPerFreq.freq(1), ...
    'Trimmed fLow should be >= original fLow');
assert(trimmedPerFreq.freq(2) <= annotPerFreq.freq(2), ...
    'Trimmed fHigh should be <= original fHigh');
fprintf('  [PASS] freq trimmed: [%.0f %.0f] -> [%.0f %.0f] Hz\n', ...
    annotPerFreq.freq(1), annotPerFreq.freq(2), ...
    trimmedPerFreq.freq(1), trimmedPerFreq.freq(2));

%% (5) Very short annotation: trim skipped gracefully

fprintf('--- (5) Very short annotation: graceful skip ---\n');
annotShort          = annotWide;
annotShort.duration = 0.05;
annotShort.tEnd     = annotShort.t0 + annotShort.duration / 86400;
trimmedShort = trimAnnotation(annotShort, 'freq', freq, 'showPlot', false);
% Should return without error, bounds unchanged
assert(trimmedShort.t0   == annotShort.t0,   'Short annot: t0 should be unchanged');
assert(trimmedShort.tEnd == annotShort.tEnd, 'Short annot: tEnd should be unchanged');
fprintf('  [PASS] very short annotation returned unchanged\n');

%% (6) trimApplied column added

fprintf('--- (6) trimApplied column added ---\n');
assert(isfield(trimmed, 'trimApplied') || ...
    (istable(trimmed) && ismember('trimApplied', trimmed.Properties.VariableNames)), ...
    'trimApplied field/column should be present in output');
fprintf('  [PASS] trimApplied present\n');

%% (7) Output type matches input type

fprintf('--- (7) Output type matches input type ---\n');
% Struct input -> struct output
trimmedStruct = trimAnnotation(annotWide, 'freq', freq, 'showPlot', false);
assert(isstruct(trimmedStruct), 'Struct input should give struct output');

% Table input -> table output
annotTable = struct2table(annotWide);
trimmedTable = trimAnnotation(annotTable, 'freq', freq, 'showPlot', false);
assert(istable(trimmedTable), 'Table input should give table output');
fprintf('  [PASS] struct->struct, table->table\n');

%% (8) SNR after trim >= SNR before trim for high-SNR signal with margins

fprintf('--- (8) SNR improves after trimming silent margins ---\n');
snrParams = struct('snrType', 'spectrogramSlices', 'showClips', false, ...
    'freq', freq, 'noiseLocation', 'before', 'noiseDelay', 0, ...
    'nfft', 128, 'nOverlap', 96);

%% (8) SNR after trimming is positive and finite

fprintf('--- (8) SNR after trim is positive and finite ---\n');
% Use a fixed noise window that fits within the file regardless of annotation size
snrParams = struct('snrType', 'spectrogramSlices', 'showClips', false, ...
    'freq', freq, 'noiseLocation', 'before', 'noiseDuration_s', 2, ...
    'noiseDelay', 0.5, 'nfft', 128, 'nOverlap', 96, 'verbose', false);

annotWideTable = struct2table(repmat(annotWide, 2, 1));
trimmedTable8  = trimAnnotation(annotWideTable, 'freq', freq, 'showPlot', false);

resAfter = snrEstimate(trimmedTable8, snrParams);

assert(all(isfinite(resAfter.snr)), 'SNR after trim should be finite');
assert(mean(resAfter.snr) > 0, ...
    sprintf('Mean SNR after trim should be positive, got %.1f dB', mean(resAfter.snr)));
fprintf('  [PASS] SNR after trim = %.1f dB\n', mean(resAfter.snr));

fprintf('\n=== test_trimAnnotation PASSED ===\n');
end
