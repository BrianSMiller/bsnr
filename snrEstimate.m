function [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = snrEstimate(annot, params)
% Measure the signal-to-noise ratio (SNR) of one or more acoustic detections.
%
% The noise floor is computed from a time segment adjacent to each event,
% with the same bandwidth and duration as the event.
%
% For a scalar annotation, results are returned as scalars.
% For a vector of annotations, results are returned as a table. Processing
% is serial below params.parallelThreshold detections and parallel above it.
%
% INPUTS
%   annot  - Scalar struct, struct array, or table of detections.
%            Required fields per element:
%              .soundFolder   path to folder of wav files (see wavFolderInfo)
%              .t0, .tEnd     Matlab datenums for detection start/end
%              .duration      detection duration in seconds
%              .freq          [lowHz highHz] frequency band of detection
%              .channel       recording channel index
%
%            TODO(annotation-interface): Replace direct field access with
%            calls to the standardised annotation accessor once the
%            cross-module interface refactor is complete.
%
%   params - Optional struct of analysis parameters. All fields optional:
%              .parallelThreshold  Min annotations to trigger parfor.
%                                  Default: 100. Set Inf to force serial,
%                                  1 to force parallel.
%              .noiseDelay         Gap in seconds between signal and noise
%                                  windows. Default: 0.5 s.
%              .noiseDuration      Noise window placement strategy:
%                                    'beforeAndAfter'       (default)
%                                    'before'
%                                    '25sBefore'
%                                    '30sBeforeAndAfter'
%                                    'randomBeforeAndAfter'
%              .freq               Override [lowHz highHz] frequency band.
%                                  Falls back to annot.freq if absent.
%              .snrType            Power estimation method:
%                                    'spectrogram'          (default)
%                                    'spectrogramSlices'
%                                    'timeDomain'
%                                    'ridge'
%                                    'synchrosqueeze'
%                                    'quantiles'    (within-window percentile;
%                                                   see Miller et al. 2022)
%                                    'nist'         (frame energy histogram;
%                                                   Ellis 2011 / NIST STNR)
%              .ridgeParams        Sub-struct for ridge and synchrosqueeze:
%                                    .ridgePenalty  tfridge penalty (default 1)
%                                    .guardBins     bins excluded around ridge
%                                                   (default 2)
%              .useLurton          If true, use Lurton (2010) eq. 6.26:
%                                    SNR = 10*log10((S-N)^2 / noiseVar)
%                                  If false (default), use simple power ratio:
%                                    SNR = 10*log10(rmsSignal / rmsNoise)
%                                  See Miller et al. (2021) for usage.
%              .showClips          Plot signal/noise spectrogram (scalar
%                                  input only). Default false. Ignored
%                                  (with a warning) in parallel mode.
%              .pauseAfterPlot     Pause after each plot. Default true.
%                                  Set false for automated review.
%              .spectroParams      Sub-struct for plot appearance.
%              .removeClicks       Click suppression parameters:
%                                    .threshold  (default 3)
%                                    .power      (default 1000)
%              .metadata           Recording metadata for calibration.
%
% OUTPUTS - scalar input
%   snr        SNR in dB
%   rmsSignal  RMS signal power (linear)
%   rmsNoise   RMS noise power (linear)
%   noiseVar   Variance of noise power (same units as rmsSignal^2)
%   fileInfo   File info struct from getAudioFromFiles
%
% OUTPUTS - vector input
%   snr        Table with columns: snr, signalRMSdB, noiseRMSdB, noiseVar
%              When params.metadata is provided, also includes:
%              signalBandLevel_dBuPa  Band-integrated signal level (dB re 1 uPa)
%              noiseBandLevel_dBuPa   Band-integrated noise level  (dB re 1 uPa)
%              Both are total band power: 10*log10(sum(PSD)*df) integrated
%              across the annotation frequency band, equivalent to
%              bandpower(psdCal, f, freq, 'psd') in calibratedPsdExample.m
%   rmsSignal, rmsNoise, noiseVar, fileInfo are empty ([]) for vector input.
%
% Brian Miller, Australian Antarctic Division, 2017.
% Refactored 2025.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Input handling
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if nargin < 2 || isempty(params)
    params = struct();
end

if istable(annot)
    annot = table2struct(annot);
end

params = applyParamDefaults(params);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Dispatch: scalar vs vector
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if numel(annot) > 1
    [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = ...
        processBatch(annot, params);
else
    [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = ...
        processOne(annot, params);
end

end % snrEstimate

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Batch dispatcher (serial or parallel depending on count)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [resultTable, rmsSignal, rmsNoise, noiseVar, fileInfo] = ...
    processBatch(annot, params)

nDet      = numel(annot);
useParfor = nDet >= params.parallelThreshold;

if useParfor && params.showClips
    warning('snrEstimate:noParallelPlots', ...
        'showClips is not supported in parallel mode and has been disabled.');
    params.showClips = false;
end

snrVec      = nan(nDet, 1);
sigVec      = nan(nDet, 1);
noiseVec    = nan(nDet, 1);
noiseVarVec = nan(nDet, 1);

fprintf('SNR analysis started:  %s\n', char(datetime('now')));
fprintf('%d annotations to process', nDet);

if useParfor
    fprintf(' (parallel)\n');
    fprintf('Progress:\n');
    fprintf('0          25          50          75         100%%\n');
    fprintf('|----------|-----------|-----------|----------|\n ');

    if isempty(gcp('nocreate'))
        parpool('Processes', max(1, feature('numcores') - 1));
    end

    D       = parallel.pool.DataQueue;
    afterEach(D, @(~) fprintf('#'));
    progInc = max(1, floor(nDet / 50));

    parfor i = 1:nDet
        [snrVec(i), sigVec(i), noiseVec(i), noiseVarVec(i)] = ...
            processOne(annot(i), params);                                   %#ok<PFBNS>
        if rem(i, progInc) == 0 || i == nDet
            send(D, i);
        end
    end
    fprintf('\n');

else
    fprintf(' (serial)\n');
    str = '';
    tic;
    for i = 1:nDet
        [snrVec(i), sigVec(i), noiseVec(i), noiseVarVec(i)] = ...
            processOne(annot(i), params);
        if rem(i, 10) == 0 || i == nDet
            fprintf(repmat('\b', 1, length(str)));
            str = sprintf('%d/%d completed in %.1f s', i, nDet, toc);
            fprintf('%s', str);
        end
    end
    fprintf('\n');
end

fprintf('SNR analysis completed: %s\n', char(datetime('now')));

snrCol      = snrVec;
signalRMSdB = 10 * log10(sigVec);
noiseRMSdB  = 10 * log10(noiseVec);
resultTable = table(snrCol, signalRMSdB, noiseRMSdB, noiseVarVec, ...
    'VariableNames', {'snr', 'signalRMSdB', 'noiseRMSdB', 'noiseVar'});

% When metadata is provided, add calibrated acoustic level columns.
% snrType determines the unit convention of rmsSignal/rmsNoise:
%   timeDomain:  rmsSignal in uPa^2  -> signalLevel = 10*log10(rmsSignal)
%   spectrogram: rmsSignal in uPa^2/Hz -> signalLevel = 10*log10(rmsSignal*bandwidth)
% For vector input we use the params from the first annotation as representative.
if ~isempty(params.metadata)
    if ~isempty(params.freq)
        bandwidth = diff(params.freq);
    elseif isstruct(annot) && isfield(annot(1), 'freq')
        bandwidth = diff(annot(1).freq);
    else
        bandwidth = 1;
    end
    if isempty(bandwidth) || bandwidth <= 0, bandwidth = 1; end
    % rmsSignal from all methods is total band power in uPa^2 (with calibration)
    % or WAV^2 (without). 10*log10(rmsSignal) = dB re 1 uPa directly.
    % timeDomain: mean(sigFilt^2) = mean instantaneous power in uPa^2
    % spectrogram: mean(sum(PSD)*df) = mean total band power in uPa^2
    signalBandLevel_dBuPa = signalRMSdB;
    noiseBandLevel_dBuPa  = noiseRMSdB;
    resultTable.signalBandLevel_dBuPa = signalBandLevel_dBuPa;
    resultTable.noiseBandLevel_dBuPa  = noiseBandLevel_dBuPa;
end

[rmsSignal, rmsNoise, noiseVar, fileInfo] = deal([], [], [], []);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Single-annotation processor
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = processOne(annot, params)

if ~isempty(params.freq)
    freq = params.freq;
else
    freq = annot.freq;
end

% Spectrogram shape: target ~nSlices windows across the detection.
% TODO: expose nSlices and overlap through params when needed.
nSlices = 30;
overlap = 0.75;

%--------------------------------------------------------------------------
% Load signal audio
%--------------------------------------------------------------------------

% wavFolderInfo prints a message and returns with no output assigned
% when the folder does not exist or contains no WAV files. Catch both
% the unassigned-output error and the empty-struct case.
try
    soundFolder = wavFolderInfo(annot.soundFolder);
catch
    soundFolder = [];
end
if isempty(soundFolder)
    [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = deal(nan, nan, nan, nan, []);
    return
end

nativeRate = soundFolder(1).sampleRate;

[annot.audio, ~, annot.fileInfo] = getAudioFromFiles( ...
    soundFolder, annot.t0, annot.tEnd, newRate=nativeRate);

fileInfo = annot.fileInfo;
if isempty(annot.fileInfo) || isempty(annot.audio)
    [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = deal(nan, nan, nan, nan, []);
    return
end

sampleRate = annot.fileInfo(1).sampleRate;

% Only compute spectrogram parameters for methods that need them
needsSpectrogram = ~any(strcmpi(params.snrType, {'timeDomain'}));
% Note: 'ridge' uses spectrogram params (nfft, nOverlap) computed below
if needsSpectrogram
    nfft     = 2^nextpow2(floor(annot.duration / nSlices / overlap * sampleRate));
    nOverlap = floor(nfft * overlap);
    if annot.duration * sampleRate < nfft
        [snr, rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan, nan);
        return
    end
else
    nfft     = [];
    nOverlap = [];
end

%--------------------------------------------------------------------------
% Build noise window
%--------------------------------------------------------------------------

[noise, excludeTimes] = buildNoiseWindow(annot, params);

[noise.audio, ~, ~] = getAudioFromFiles(soundFolder, ...
    noise.t0, noise.tEnd, exclusions=excludeTimes, channel=noise.channel);

if needsSpectrogram && size(noise.audio, 1) < nfft
    [snr, rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan, nan);
    return
end

%--------------------------------------------------------------------------
% Optional click removal
%--------------------------------------------------------------------------

if ~isempty(params.removeClicks)
    annot.audio = removeClicks(annot.audio, ...
        params.removeClicks.threshold, params.removeClicks.power);
    noise.audio = removeClicks(noise.audio, ...
        params.removeClicks.threshold, params.removeClicks.power);
end

%--------------------------------------------------------------------------
% Estimate signal and noise power
%--------------------------------------------------------------------------

sigFilt   = [];
noiseFilt = [];
ridgeFreq      = [];
quantileThresh = [];

switch params.snrType
    case 'spectrogram'
        [rmsSignal, rmsNoise, noiseVar] = snrSpectrogram( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata);

    case 'spectrogramSlices'
        [rmsSignal, rmsNoise, noiseVar] = snrSpectrogramSlices( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata);

    case 'quantiles'
        [rmsSignal, rmsNoise, noiseVar, quantileThresh] = snrQuantiles( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, params.metadata);

    case 'nist'
        [rmsSignal, rmsNoise, noiseVar] = snrHistogram( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, params.metadata);

    case 'timeDomain'
        [rmsSignal, rmsNoise, noiseVar, sigFilt, noiseFilt] = ...
            snrTimeDomain(annot.audio, noise.audio, freq, sampleRate, params.metadata);

    case 'ridge'
        [rmsSignal, rmsNoise, noiseVar, ridgeFreq, ~] = snrRidge( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata, params.ridgeParams);

    case 'synchrosqueeze'
        [rmsSignal, rmsNoise, noiseVar, ridgeFreq, ~] = snrSynchrosqueeze( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata, params.ridgeParams);

    otherwise
        error('snrEstimate:unknownSnrType', ...
            'Unknown snrType ''%s''.', params.snrType);
end

%--------------------------------------------------------------------------
% Compute SNR
%--------------------------------------------------------------------------

if params.useLurton
    % Lurton (2010) eq. 6.26: SNR as a function of the difference between
    % signal and noise power relative to the variance of the noise.
    % abs() handles cases where rmsSignal < rmsNoise.
    snr = 10 * log10(abs((rmsSignal - rmsNoise).^2 / noiseVar));
else
    % Simple power ratio (default): intuitive and widely expected.
    snr = 10 * log10(rmsSignal / rmsNoise);
end

annot.rmsLevel = 10 * log10(rmsSignal);
noise.rmsLevel = 10 * log10(rmsNoise);

%--------------------------------------------------------------------------
% Optional: plot spectrogram with signal/noise annotation
%--------------------------------------------------------------------------

if params.showClips
    spectroParams = buildSpectroParams(params, annot, sampleRate, freq);
    spectroParams.snrType = params.snrType;   % for fsst vs spectrogram display routing
    if ~isempty(ridgeFreq)
        spectroParams.ridgeFreq = ridgeFreq;
    end
    if params.useLurton
        spectroParams.noiseVar = noiseVar;
    end
    if ~isempty(quantileThresh)
        spectroParams.quantileThresh = quantileThresh;
    end
    if ~isempty(excludeTimes)
        spectroParams.excludeTimes = excludeTimes;   % gap bounds for display
    end
    spectroAnnotationAndNoise(annot, noise, soundFolder, spectroParams, snr, ...
        params.metadata);

    if strcmpi(params.snrType, 'timeDomain') && ~isempty(sigFilt)
        % Load continuous clip for time-domain power plot
        clipT0    = noise.t0 - spectroParams.pre / 86400;
        clipTEnd  = max([annot.tEnd, noise.tEnd]) + spectroParams.post / 86400;
        clipAudio = getAudioFromFiles(soundFolder, clipT0, clipTEnd, ...
            channel=annot.channel, newRate=sampleRate);
        figure();
        plotTimeDomainPower(clipAudio, clipT0, annot, noise, ...
            freq, sampleRate, rmsSignal, rmsNoise, noiseVar);
    end

    if params.pauseAfterPlot
        pause;
    end
end

end % processOne

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function params = applyParamDefaults(params)

if ~isfield(params, 'parallelThreshold') || isempty(params.parallelThreshold)
    params.parallelThreshold = 100;
end
if ~isfield(params, 'noiseDelay') || isempty(params.noiseDelay)
    params.noiseDelay = 0.5;   % 0.5 s gap between signal and noise windows
end
if ~isfield(params, 'noiseDuration') || isempty(params.noiseDuration)
    params.noiseDuration = 'beforeAndAfter';
end
if ~isfield(params, 'snrType') || isempty(params.snrType)
    params.snrType = 'spectrogram';
end
if ~isfield(params, 'useLurton') || isempty(params.useLurton)
    params.useLurton = false;
end
if ~isfield(params, 'freq')
    params.freq = [];
end
if ~isfield(params, 'showClips') || isempty(params.showClips)
    params.showClips = false;
end
if ~isfield(params, 'metadata')
    params.metadata = [];
end
if ~isfield(params, 'pauseAfterPlot') || isempty(params.pauseAfterPlot)
    params.pauseAfterPlot = true;
end
if ~isfield(params, 'ridgeParams') || isempty(params.ridgeParams)
    params.ridgeParams = struct();
end
if ~isfield(params, 'removeClicks')
    params.removeClicks = [];
else
    if ~isfield(params.removeClicks, 'threshold')
        params.removeClicks.threshold = 3;
    end
    if ~isfield(params.removeClicks, 'power')
        params.removeClicks.power = 1000;
    end
end

end

% -------------------------------------------------------------------------

function [noise, excludeTimes] = buildNoiseWindow(annot, params)

noise        = annot;
excludeTimes = [];

switch params.noiseDuration
    case 'before'
        noise.tEnd = annot.t0   - params.noiseDelay / 86400;
        noise.t0   = noise.tEnd - annot.duration    / 86400;

    case '25sBefore'
        % 25 s window before the detection - as requested by Franciele
        % Castro for SORP ATWG post-doc analysis.
        noise.tEnd = annot.t0   - params.noiseDelay / 86400;
        noise.t0   = noise.tEnd - 25               / 86400;

    case '30sBeforeAndAfter'
        noise.t0   = annot.t0   - (30 + params.noiseDelay) / 86400;
        noise.tEnd = annot.tEnd + (30 + params.noiseDelay) / 86400;
        excludeTimes = [annot.t0 annot.tEnd] + params.noiseDelay * ([-1 1] / 86400);

    case 'randomBeforeAndAfter'
        randDelay  = rand * params.noiseDelay;
        noise.t0   = annot.t0   - (0.5 * annot.duration + randDelay) / 86400;
        noise.tEnd = annot.tEnd + (0.5 * annot.duration + randDelay) / 86400;
        excludeTimes = [annot.t0 annot.tEnd] + randDelay * ([-1 1] / 86400);

    otherwise % 'beforeAndAfter' (default)
        noise.t0   = annot.t0   - (0.5 * annot.duration + params.noiseDelay) / 86400;
        noise.tEnd = annot.tEnd + (0.5 * annot.duration + params.noiseDelay) / 86400;
        excludeTimes = [annot.t0 annot.tEnd] + params.noiseDelay * ([-1 1] / 86400);
end

end

% -------------------------------------------------------------------------

function spectroParams = buildSpectroParams(params, annot, sampleRate, freq)

if isfield(params, 'spectroParams') && ~isempty(params.spectroParams)
    spectroParams = params.spectroParams;
    if ~isfield(spectroParams, 'freq')
        spectroParams.freq = freq;
    end
    return
end

overlapPercent = 0.75;
win            = floor(sampleRate / 4);

spectroParams.pre         = 1;
spectroParams.post        = 1;
spectroParams.win         = win;
spectroParams.overlap     = floor(win * overlapPercent);
spectroParams.yLims       = [10 125];
spectroParams.freq        = annot.freq;
spectroParams.noiseDelay  = params.noiseDelay / 86400;

end

