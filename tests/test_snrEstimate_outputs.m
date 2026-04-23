function test_snrEstimate_outputs()
% Tests for snrEstimate input flexibility.
%
% Tests:
%   (1) datetime t0/tEnd accepted and produce same result as datenum
%   (2) Backward compatibility — existing 5-output call still works

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

snrDN = snrEstimate(annotDN, params);
snrDT = snrEstimate(annotDT, params);

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

fprintf('\n=== test_snrEstimate_outputs PASSED ===\n');
end
