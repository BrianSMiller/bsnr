% run_tests.m
% Test driver for snrEstimate and associated SNR method functions.
%
% USAGE
%   cd C:\analysis\bsnr
%   run_tests

% Add source root and tests folder to FRONT of path so bsnr functions
% take precedence over any same-named functions in other toolboxes.
sourceDir = fileparts(mfilename('fullpath'));
testsDir  = fullfile(sourceDir, 'tests');
addpath(sourceDir, '-begin');
addpath(testsDir,  '-begin');

% Add longTermRecorders dependency if available and not already on path.
% This provides getAudioFromFiles, wavFolderInfo, doTimespansOverlap, etc.
% bsnr paths are already at the front so its versions take precedence.
% Dependencies required by bsnr (in load order):
%   longTermRecorders  — wavFolderInfo, getAudioFromFiles, removeClicks
%   annotatedLibrary   — doTimespansOverlap, getInclusionTimes
% External dependencies required by bsnr.
% Each entry: {display_name, {candidate_path_1, candidate_path_2, ...}}
% Paths are added only if the directory exists and is not already on the path.
% bsnr source is already at the front so its versions take precedence.
analysisRoot = 'C:\analysis';
deps = {
    'longTermRecorders', fullfile(analysisRoot, 'longTermRecorders')
    'annotatedLibrary',  fullfile(analysisRoot, 'annotatedLibrary')
    'bsmTools',          fullfile(analysisRoot, 'bsmTools')   % removeClicks now in bsnr; keep for other tools
    'soundFolder',       fullfile(analysisRoot, 'soundFolder')
};
pathDirs = strsplit(path, pathsep);
for d = 1:size(deps, 1)
    name = deps{d, 1};
    dir_ = deps{d, 2};
    if exist(dir_, 'dir') && ~any(strcmp(pathDirs, dir_))
        addpath(dir_);
        fprintf('Added dependency: %s\n', name);
    elseif ~exist(dir_, 'dir')
        fprintf('Warning: dependency not found: %s (%s)\n', name, dir_);
    end
end

% Re-assert bsnr source at path front after adding dependencies.
% annotatedLibrary may contain stale copies of bsnr files; putting
% bsnr at the front ensures our versions always win.
addpath(sourceDir, '-begin');
addpath(testsDir,  '-begin');

% Verify key bsnr functions resolve to our source, not stale copies
bsnrFns = {'spectroAnnotationAndNoise', 'snrEstimate', 'removeClicks'};
for fi = 1:numel(bsnrFns)
    w = which(bsnrFns{fi});
    if ~contains(w, sourceDir)
        warning('run_tests:stalePath', ...
            '%s resolves to %s (not bsnr source).\nRun: addpath(''%s'',''-begin'')', ...
            bsnrFns{fi}, w, sourceDir);
        % Force it
        addpath(sourceDir, '-begin');
        addpath(testsDir,  '-begin');
    end
end

% Sanity check: wavFolderInfo must accept a char path
try
    wfi = wavFolderInfo(tempdir);
catch wfiErr
    warning('run_tests:wavFolderInfo', ...
        ['wavFolderInfo failed for a char path: %s\n' ...
         'Check that the correct version is on the MATLAB path.\n' ...
         'Try: addpath(''%s'', ''-begin'')'], ...
        wfiErr.message, sourceDir);
end

fprintf('==============================================\n');
fprintf('  snrEstimate test suite\n');
fprintf('  %s\n', datestr(now));
fprintf('==============================================\n\n');

reply = input('Run plot tests? Displays spectrograms of test signals. [Y/n]: ', 's');
if isempty(reply), reply = 'y'; end
runPlots = ~strcmpi(strtrim(reply), 'n');
fprintf('Plot tests %s.\n\n', onOff(runPlots));

reply = input('Run parallel batch test? Starting a parpool may take ~30 s. [y/N]: ', 's');
if isempty(reply), reply = 'n'; end
runParallel = strcmpi(strtrim(reply), 'y');
fprintf('Parallel test %s.\n\n', onOff(runParallel));

reply = input('Verbose output? Shows [PASS] lines. [y/N]: ', 's');
if isempty(reply), reply = 'n'; end
verbose = strcmpi(strtrim(reply), 'y');
fprintf('Verbose output %s.\n\n', onOff(verbose));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Run tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[passed(1), elapsed(1)]  = runOne('test_snrMethods', verbose,              @() test_snrMethods());
[passed(2), elapsed(2)]  = runOne('test_snrEstimate_scalar', verbose, @() test_snrEstimate_scalar());
[passed(3), elapsed(3)]  = runOne('test_snrEstimate_correctness', verbose, @() test_snrEstimate_correctness());
[passed(4), elapsed(4)]  = runOne('test_snrEstimate_methods', verbose, @() test_snrEstimate_methods());
[passed(5), elapsed(5)]  = runOne('test_removeClicks', verbose, @() test_removeClicks());
[passed(6), elapsed(6)]  = runOne('test_calibration', verbose, @() test_calibration());

if runPlots
    [passed(7), elapsed(7)] = runOne('test_plots', verbose, @() test_plots());
    [passed(8), elapsed(8)] = runOne('test_snrEstimate_batch', verbose, @() test_snrEstimate_batch(runParallel));
    [passed(9), elapsed(9)] = runOne('test_snrEstimate_noiseWindows', verbose, @() test_snrEstimate_noiseWindows());
    [passed(10), elapsed(10)] = runOne('test_snrEstimate_outputs', verbose, @() test_snrEstimate_outputs());
    [passed(11), elapsed(11)] = runOne('test_trimAnnotation', verbose, @() test_trimAnnotation());
    nTests = 11;
else
    [passed(7), elapsed(7)] = runOne('test_snrEstimate_batch', verbose, @() test_snrEstimate_batch(runParallel));
    [passed(8), elapsed(8)] = runOne('test_snrEstimate_noiseWindows', verbose, @() test_snrEstimate_noiseWindows());
    [passed(9), elapsed(9)] = runOne('test_snrEstimate_outputs', verbose, @() test_snrEstimate_outputs());
    [passed(10), elapsed(10)] = runOne('test_trimAnnotation', verbose, @() test_trimAnnotation());
    nTests = 10;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Summary
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if runPlots
    names = {'test_snrMethods', 'test_snrEstimate_scalar', 'test_snrEstimate_correctness', ...
             'test_snrEstimate_methods', 'test_removeClicks', 'test_calibration', ...
             'test_plots', 'test_snrEstimate_batch', 'test_snrEstimate_noiseWindows', ...
             'test_snrEstimate_outputs', 'test_trimAnnotation'};
else
    names = {'test_snrMethods', 'test_snrEstimate_scalar', 'test_snrEstimate_correctness', ...
             'test_snrEstimate_methods', 'test_removeClicks', 'test_calibration', ...
             'test_snrEstimate_batch', 'test_snrEstimate_noiseWindows', ...
             'test_snrEstimate_outputs', 'test_trimAnnotation'};
end

fprintf('\n==============================================\n');
if ~verbose
    fprintf('  %d/%d passed\n', sum(passed), nTests);
else
    fprintf('  Results\n');
    fprintf('==============================================\n');
    for i = 1:nTests
        if passed(i), status = 'PASS'; else, status = 'FAIL'; end
        fprintf('  [%s]  %-40s  %.1f s\n', status, names{i}, elapsed(i));
    end
    fprintf('----------------------------------------------\n');
    fprintf('  %d/%d passed\n', sum(passed), nTests);
end
fprintf('==============================================\n');

if ~all(passed)
    error('run_tests:failures', '%d test(s) failed.', sum(~passed));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [passed, elapsed] = runOne(name, verbose, fn)
if nargin < 3, fn = verbose; verbose = false; end
if verbose
    fprintf('\nRunning %s...\n', name);
else
    fprintf('  %-42s', [name '...']);
end
tStart = tic;
try
    if verbose
        fn();
    else
        evalc('fn()');
    end
    passed  = true;
    elapsed = toc(tStart);
    if verbose
        % individual test already printed [PASS]
    else
        fprintf(' %5.1f s  [PASS]\n', elapsed);
    end
catch err
    passed  = false;
    elapsed = toc(tStart);
    if ~verbose, fprintf(' %5.1f s  [FAIL]\n', elapsed); end
    fprintf('    Error: %s\n', err.message);
    if ~isempty(err.stack)
        fprintf('    at %s (line %d)\n', err.stack(1).name, err.stack(1).line);
    end
end
end

function s = onOff(tf)
if tf, s = 'ENABLED'; else, s = 'SKIPPED'; end
end
