function test_parallel_performance()
% Parallel performance benchmark for snrEstimate and trimAnnotation.
%
% Measures wall-clock speedup of parfor vs serial processing at three
% workload sizes. Not a pass/fail test — prints a speedup table.
%
% Run time: ~2-5 min depending on parpool startup and hardware.
% Requires Parallel Computing Toolbox.
%
% USAGE
%   test_parallel_performance          % runs all sizes
%   test_parallel_performance          % from run_tests with verbose=true

fprintf('\n=== test_parallel_performance ===\n');

if isempty(ver('parallel'))
    fprintf('  Parallel Computing Toolbox not available — skipping.\n');
    fprintf('\n=== test_parallel_performance SKIPPED ===\n');
    return
end

%% Shared fixture parameters
sampleRate = 1000;
durSec     = 4;
freq       = [25 90];
sizes      = [100, 500, 1000];

fprintf('\n  Building test fixtures...\n');
[annotBase, cleanup] = createTestFixture( ...
    'durationSec', durSec, 'freq', freq, 'sampleRate', sampleRate);
cleanupObj = onCleanup(cleanup);

%% Ensure parpool is running before timing
fprintf('  Starting parpool (may take ~30 s)...\n');
if isempty(gcp('nocreate'))
    parpool('Processes', max(1, feature('numcores') - 1));
end
nWorkers = gcp().NumWorkers;
fprintf('  Workers: %d\n\n', nWorkers);

%% snrEstimate benchmark
fprintf('  snrEstimate (spectrogramSlices, nfft=128)\n');
fprintf('  %-8s  %-10s  %-10s  %-8s\n', 'N', 'Serial(s)', 'Parallel(s)', 'Speedup');
fprintf('  %s\n', repmat('-', 1, 44));

snrParamsBase = struct('snrType', 'spectrogramSlices', 'nfft', 128, ...
    'showClips', false);

for n = sizes
    batch = repmat(annotBase, n, 1);

    % Serial
    p = snrParamsBase; p.parallelThreshold = n+1;
    tSerial = tic;
    snrEstimate(batch, p);
    tS = toc(tSerial);

    % Parallel
    p = snrParamsBase; p.parallelThreshold = 1;
    tPar = tic;
    snrEstimate(batch, p);
    tP = toc(tPar);

    speedup = tS / tP;
    fprintf('  %-8d  %-10.1f  %-10.1f  %.1fx\n', n, tS, tP, speedup);
end

%% trimAnnotation benchmark
fprintf('\n  trimAnnotation (centroid, nfft=128)\n');
fprintf('  %-8s  %-10s  %-10s  %-8s\n', 'N', 'Serial(s)', 'Parallel(s)', 'Speedup');
fprintf('  %s\n', repmat('-', 1, 44));

trimParams = {'freq', freq, 'nfft', 128, 'showPlot', false};

for n = sizes
    batch = repmat(annotBase, n, 1);

    % Serial
    tSerial = tic;
    trimAnnotation(batch, trimParams{:}, 'parallelThreshold', n+1);
    tS = toc(tSerial);

    % Parallel
    tPar = tic;
    trimAnnotation(batch, trimParams{:}, 'parallelThreshold', 1);
    tP = toc(tPar);

    speedup = tS / tP;
    fprintf('  %-8d  %-10.1f  %-10.1f  %.1fx\n', n, tS, tP, speedup);
end

fprintf('\n  Workers: %d  |  Hardware: %s\n', nWorkers, computer);
fprintf('\n=== test_parallel_performance COMPLETE ===\n');
end
