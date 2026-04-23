% run_tests.m
% Test driver for snrEstimate and associated SNR method functions.
%
% USAGE
%   cd C:\analysis\bsnr\tests
%   run_tests

% Add source root and tests folder to FRONT of path so bsnr functions
% take precedence over any same-named functions in other toolboxes.
thisDir   = fileparts(mfilename('fullpath'));
sourceDir = fileparts(thisDir);
addpath(thisDir,   '-begin');
addpath(sourceDir, '-begin');

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
addpath(thisDir,   '-begin');
addpath(sourceDir, '-begin');

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
        addpath(thisDir,   '-begin');
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Run tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[passed(1), elapsed(1)] = runOne('test_snrMethods',           @() test_snrMethods());
[passed(2), elapsed(2)] = runOne('test_removeClicks',         @() test_removeClicks());
[passed(3), elapsed(3)] = runOne('test_snrEstimate_scalar', @() test_snrEstimate_scalar());
[passed(4), elapsed(4)] = runOne('test_calibration',          @() test_calibration());

if runPlots
    [passed(5), elapsed(5)] = runOne('test_plots',                    @() test_plots());
    [passed(6), elapsed(6)] = runOne('test_snrEstimate_batch',        @() test_snrEstimate_batch(runParallel));
    [passed(7), elapsed(7)] = runOne('test_snrEstimate_noiseWindows', @() test_snrEstimate_noiseWindows());
    [passed(8), elapsed(8)] = runOne('test_snrEstimate_outputs',      @() test_snrEstimate_outputs());
    [passed(9), elapsed(9)] = runOne('test_trimAnnotation',           @() test_trimAnnotation());
    nTests = 9;
else
    [passed(5), elapsed(5)] = runOne('test_snrEstimate_batch',        @() test_snrEstimate_batch(runParallel));
    [passed(6), elapsed(6)] = runOne('test_snrEstimate_noiseWindows', @() test_snrEstimate_noiseWindows());
    [passed(7), elapsed(7)] = runOne('test_snrEstimate_outputs',      @() test_snrEstimate_outputs());
    [passed(8), elapsed(8)] = runOne('test_trimAnnotation',           @() test_trimAnnotation());
    nTests = 8;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Summary
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if runPlots
    names = {'test_snrMethods', 'test_removeClicks', 'test_snrEstimate_scalar', ...
             'test_calibration', 'test_plots', 'test_snrEstimate_batch', ...
             'test_snrEstimate_noiseWindows', 'test_snrEstimate_outputs', 'test_trimAnnotation'};
else
    names = {'test_snrMethods', 'test_removeClicks', 'test_snrEstimate_scalar', ...
             'test_calibration', 'test_snrEstimate_batch', ...
             'test_snrEstimate_noiseWindows', 'test_snrEstimate_outputs', 'test_trimAnnotation'};
end

fprintf('\n==============================================\n');
fprintf('  Results\n');
fprintf('==============================================\n');
for i = 1:nTests
    if passed(i), status = 'PASS'; else, status = 'FAIL'; end
    fprintf('  [%s]  %-35s  %.1f s\n', status, names{i}, elapsed(i));
end
fprintf('----------------------------------------------\n');
fprintf('  %d/%d passed\n', sum(passed), nTests);
fprintf('==============================================\n');

if ~all(passed)
    error('run_tests:failures', '%d test(s) failed.', sum(~passed));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [passed, elapsed] = runOne(name, fn)
fprintf('\nRunning %s...\n', name);
tStart = tic;
try
    fn();
    passed  = true;
    elapsed = toc(tStart);
catch err
    passed  = false;
    elapsed = toc(tStart);
    fprintf('\n  [FAIL] %s threw an error:\n', name);
    fprintf('    %s\n', err.message);
    if ~isempty(err.stack)
        fprintf('    at %s (line %d)\n', err.stack(1).name, err.stack(1).line);
    end
end
end

function s = onOff(tf)
if tf, s = 'ENABLED'; else, s = 'SKIPPED'; end
end
