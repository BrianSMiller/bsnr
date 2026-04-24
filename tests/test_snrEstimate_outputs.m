function test_snrEstimate_outputs()
% Tests for snrEstimate input flexibility and output correctness.
%
% Tests:
%   (1) datetime t0/tEnd accepted and produce same result as datenum
%   (2) Backward compatibility — existing 5-output call still works
%   (3) resolvedParams returned as 6th output
%   (4) resolvedParams.nfft is derived when not set explicitly
%   (5) resolvedParams.nfft matches explicitly set value

fprintf('\n=== test_snrEstimate_outputs ===\n');

sampleRate = 1000;
durSec     = 5;
freq       = [25 29];

%% (1) datetime t0/tEnd produces same result as datenum

fprintf('--- (1) datetime input matches datenum input ---\n');
[annotDN, cleanup1] = createTestFixture( ...
    'durationSec', durSec, 'freq', freq, 'sampleRate', sampleRate);
cleanupObj1 = onCleanup(cleanup1);

annotDT      = annotDN;
annotDT.t0   = datetime(annotDN.t0,   'ConvertFrom', 'datenum');
annotDT.tEnd = datetime(annotDN.tEnd, 'ConvertFrom', 'datenum');

params = struct('snrType', 'spectrogramSlices', 'showClips', false, ...
    'nfft', 128, 'nOverlap', 96);

snrDN = snrEstimate(annotDN, params).snr(1);
snrDT = snrEstimate(annotDT, params).snr(1);

assert(isfinite(snrDN) && isfinite(snrDT), ...
    'Both datenum and datetime inputs should produce finite SNR');
assert(abs(snrDN - snrDT) < 1e-6, ...
    sprintf('datetime and datenum should produce identical SNR (diff=%.2e)', ...
    abs(snrDN - snrDT)));
fprintf('  [PASS] datetime input produces identical SNR to datenum (diff=%.2e)\n', ...
    abs(snrDN - snrDT));

%% (2) Backward compatibility — batch output is still a table with snr column

fprintf('--- (2) Batch output backward compatibility ---\n');
[annotBase, cleanup2] = createTestFixture( ...
    'durationSec', durSec, 'freq', freq, 'sampleRate', sampleRate);
cleanupObj2 = onCleanup(cleanup2);
annotBatch = repmat(annotBase, 3, 1);

res = snrEstimate(annotBatch, ...
    struct('snrType', 'spectrogramSlices', 'showClips', false, 'verbose', false));

assert(istable(res), 'Batch output should be a table');
assert(ismember('snr', res.Properties.VariableNames), ...
    'Batch output table should have snr column');
assert(height(res) == 3, 'Batch output should have 3 rows');
fprintf('  [PASS] batch output is a table with snr column (%d rows)\n', height(res));

%% (3) resolvedParams returned as 6th output

fprintf('--- (3) resolvedParams is a struct with expected fields ---\n');
[annotRp, cleanupRp] = createTestFixture( ...
    'durationSec', durSec, 'freq', freq, 'sampleRate', sampleRate);
cleanupObjRp = onCleanup(cleanupRp);

[~, ~, ~, ~, ~, rp] = snrEstimate(annotRp, ...
    struct('snrType', 'spectrogram', 'showClips', false, 'nfft', 128));

assert(isstruct(rp), 'resolvedParams should be a struct');
for f = {'snrType', 'nfft', 'nOverlap', 'noiseLocation', 'noiseDelay'}
    assert(isfield(rp, f{1}), sprintf('resolvedParams missing field: %s', f{1}));
end
assert(strcmp(rp.snrType, 'spectrogram'), 'resolvedParams.snrType should be ''spectrogram''');
assert(rp.nfft == 128, sprintf('resolvedParams.nfft should be 128, got %d', rp.nfft));
fprintf('  [PASS] resolvedParams is a struct with expected fields\n');

%% (4) resolvedParams.nfft is derived when not set explicitly

fprintf('--- (4) resolvedParams.nfft derived when not set ---\n');
[~, ~, ~, ~, ~, rpDerived] = snrEstimate(annotRp, ...
    struct('snrType', 'spectrogram', 'showClips', false, 'verbose', false));

assert(isstruct(rpDerived), 'resolvedParams should be a struct');
assert(~isempty(rpDerived.nfft) && rpDerived.nfft > 0, ...
    'resolvedParams.nfft should be a positive integer when derived');
assert(rpDerived.nfft == 2^round(log2(rpDerived.nfft)), ...
    'resolvedParams.nfft should be a power of 2');
fprintf('  [PASS] resolvedParams.nfft derived as power of 2: %d\n', rpDerived.nfft);

%% (5) resolvedParams.nfft matches explicitly set value

fprintf('--- (5) resolvedParams.nfft matches explicit setting ---\n');
[~, ~, ~, ~, ~, rpExplicit] = snrEstimate(annotRp, ...
    struct('snrType', 'spectrogram', 'showClips', false, 'nfft', 256));

assert(rpExplicit.nfft == 256, ...
    sprintf('resolvedParams.nfft should be 256, got %d', rpExplicit.nfft));
fprintf('  [PASS] resolvedParams.nfft == 256 (explicitly set)\n');

fprintf('\n=== test_snrEstimate_outputs PASSED ===\n');
end
