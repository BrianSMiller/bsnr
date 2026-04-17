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
%              .verbose            Print progress output. Default: true.
%                                  Set false to suppress all output.
%              .nfft               FFT length in samples for spectrogram-based
%                                  methods. When set, this is used directly
%                                  and recorded in the output for
%                                  reproducibility. Default: [] (derive from
%                                  nSlices).
%                                  IMPORTANT: for batch processing, nfft must
%                                  be constant across all annotations for
%                                  results to be comparable. When not set,
%                                  nfft is derived from the median annotation
%                                  duration and a warning is issued. The
%                                  fraction of annotations too short for the
%                                  chosen nfft is also reported; if >= 10%
%                                  a stronger warning suggests reducing nfft.
%              .nOverlap           FFT overlap in samples. Default: [] (set
%                                  to floor(nfft * 0.75) automatically).
%              .nSlices            Target number of STFT windows across the
%                                  detection. Used to derive nfft when
%                                  params.nfft is not set:
%                                    nfft = 2^nextpow2(duration/nSlices/0.75
%                                                      * sampleRate)
%                                  Default: 30.
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
%              .useLurton          If true, use Lurton (2010, eq. 6.26):
%                                    SNR = 10*log10((S-N)^2 / noiseVar)
%                                  If false (default), use simple power ratio:
%                                    SNR = 10*log10(rmsSignal / rmsNoise)
%                                  See Miller et al. (2021) for usage.
%              .showClips          Plot signal/noise spectrogram (scalar
%                                  input only). Default false. Ignored
%                                  (with a warning) in parallel mode.
%              .pauseAfterPlot     Pause after each plot. Default true.
%                                  Set false for automated review.
%              .displayType        Display type when showClips=true:
%                                    'spectrogram'  (default for most methods)
%                                    'timeSeries'   per-slice band power vs time
%                                                   (per-sample for timeDomain)
%                                    'histogram'    slice power distributions
%                                  Per-method defaults:
%                                    nist      -> 'histogram'
%                                    timeDomain -> 'timeSeries'
%                                    others    -> 'spectrogram'
%              .plotParams      Optional display overrides (display-only;
%                                  win/overlap are always derived from nSlices
%                                  to match the computation window):
%                                    .yLims  [loHz hiHz] frequency axis range
%                                    .pre    seconds before noise window
%                                    .post   seconds after signal window
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

%--------------------------------------------------------------------------
% Resolve nfft/nOverlap at the batch level before any processing begins.
% A constant nfft across all annotations is essential for comparability:
% per-annotation nfft produces SNR values at different frequency resolutions
% that cannot be directly compared or reproduced without knowing each
% annotation's exact duration.
%--------------------------------------------------------------------------
if isempty(params.nfft)
    durations   = [annot.duration];
    medianDur   = median(durations);
    minDur      = min(durations);
    maxDur      = max(durations);
    sampleRate  = [];   % unknown until audio loaded; use a representative value
    % Estimate sampleRate from the first annotation's folder if possible
    try
        sf = wavFolderInfo(annot(1).soundFolder, '', false, false);
        if ~isempty(sf), sampleRate = sf(1).sampleRate; end
    catch
    end
    if isempty(sampleRate)
        sampleRate = 2000;   % safe fallback; warn below
    end

    overlap  = 0.75;
    nfftBatch = 2^nextpow2(floor(medianDur / params.nSlices / overlap * sampleRate));
    nOverlapBatch = floor(nfftBatch * overlap);

    % Count how many annotations are too short for this nfft
    nTooShort   = sum(durations * sampleRate < nfftBatch);
    pctTooShort = 100 * nTooShort / nDet;

    baseMsg = sprintf(['nfft not set for batch of %d annotations. ' ...
        'Using median duration (%.2f s, range %.2f\x96%.2f s) ' ...
        '\x2192 nfft=%d, nOverlap=%d at %d Hz. ' ...
        '%d/%d annotations (%.0f%%) shorter than nfft will return NaN. ' ...
        'Set params.nfft explicitly for reproducible results.'], ...
        nDet, medianDur, minDur, maxDur, ...
        nfftBatch, nOverlapBatch, sampleRate, ...
        nTooShort, nDet, pctTooShort);

    if pctTooShort >= 10
        warning('snrEstimate:nfftHighTruncation', ...
            '%s\nConsider reducing params.nSlices or setting params.nfft directly.', ...
            baseMsg);
    elseif nTooShort > 0
        warning('snrEstimate:nfftTruncation', '%s', baseMsg);
    else
        warning('snrEstimate:nfftAutoSelected', '%s', baseMsg);
    end

    params.nfft    = nfftBatch;
    params.nOverlap = nOverlapBatch;
end

if useParfor && params.showClips
    warning('snrEstimate:noParallelPlots', ...
        'showClips is not supported in parallel mode and has been disabled.');
    params.showClips = false;
end

snrVec      = nan(nDet, 1);
sigVec      = nan(nDet, 1);
noiseVec    = nan(nDet, 1);
noiseVarVec = nan(nDet, 1);

if params.verbose
    fprintf('SNR analysis started:  %s\n', char(datetime('now')));
    fprintf('%d annotations to process', nDet);
end

if useParfor
    if params.verbose
        fprintf(' (parallel)\n');
        fprintf('Progress:\n');
        fprintf('0          25          50          75         100%%\n');
        fprintf('|----------|-----------|-----------|----------|\n ');
    end

    if isempty(gcp('nocreate'))
        parpool('Processes', max(1, feature('numcores') - 1));
    end

    D       = parallel.pool.DataQueue;
    if params.verbose
        afterEach(D, @(~) fprintf('#'));
    end
    progInc = max(1, floor(nDet / 50));

    parfor i = 1:nDet
        [snrVec(i), sigVec(i), noiseVec(i), noiseVarVec(i)] = ...
            processOne(annot(i), params);                                   %#ok<PFBNS>
        if rem(i, progInc) == 0 || i == nDet
            send(D, i);
        end
    end
    if params.verbose, fprintf('\n'); end

else
    if params.verbose, fprintf(' (serial)\n'); end
    str = '';
    tic;
    for i = 1:nDet
        [snrVec(i), sigVec(i), noiseVec(i), noiseVarVec(i)] = ...
            processOne(annot(i), params);
        if params.verbose && (rem(i, 10) == 0 || i == nDet)
            fprintf(repmat('\b', 1, length(str)));
            str = sprintf('%d/%d completed in %.1f s', i, nDet, toc);
            fprintf('%s', str);
        end
    end
    if params.verbose, fprintf('\n'); end
end

if params.verbose
    fprintf('SNR analysis completed: %s\n', char(datetime('now')));
end

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

% Unwrap cell-array fields that arise when table2struct converts a
% single table row — e.g. soundFolder becomes {1x1 cell} not char.
if iscell(annot.soundFolder), annot.soundFolder = annot.soundFolder{1}; end
if iscell(annot.freq),        annot.freq        = annot.freq{1};        end
if iscell(annot.t0),          annot.t0          = annot.t0{1};          end
if iscell(annot.tEnd),        annot.tEnd        = annot.tEnd{1};        end

% channel is optional — default to 1 if missing, cell-wrapped, or not a
% valid scalar (e.g. when table2struct produces a matrix from joined tables)
if ~isfield(annot, 'channel')
    annot.channel = 1;
elseif iscell(annot.channel)
    annot.channel = annot.channel{1};
end
if ~isscalar(annot.channel) || ~isnumeric(annot.channel)
    annot.channel = 1;
end

% duration is optional — compute from t0/tEnd if missing or NaN
if ~isfield(annot, 'duration') || ~isscalar(annot.duration) || ~isfinite(annot.duration)
    annot.duration = (annot.tEnd - annot.t0) * 86400;
end

% freq is optional if params.freq is set — but must exist for annot.freq fallback
if ~isfield(annot, 'freq')
    if ~isempty(params.freq)
        annot.freq = params.freq;
    else
        error('snrEstimate:missingFreq', ...
            'annot.freq is missing and params.freq is not set.');
    end
end

if ~isempty(params.freq)
    freq = params.freq;
else
    freq = annot.freq;
end

% Resolve nfft and nOverlap.
% Use params.nfft/nOverlap if explicitly set (reproducibility: the exact
% values used are recorded in the output).  Otherwise derive from nSlices.
overlap = 0.75;

%--------------------------------------------------------------------------
% Load signal audio
%--------------------------------------------------------------------------

% wavFolderInfo prints a message and returns with no output assigned
% when the folder does not exist or contains no WAV files. Catch both
% the unassigned-output error and the empty-struct case.
try
    soundFolder = wavFolderInfo(annot.soundFolder, '', false, false);
catch
    soundFolder = [];
end
if isempty(soundFolder)
    [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = deal(nan, nan, nan, nan, []);
    return
end

nativeRate  = soundFolder(1).sampleRate;
targetRate  = nativeRate;
if ~isempty(params.resampleRate)
    targetRate = params.resampleRate;
end

[annot.audio, ~, annot.fileInfo] = getAudioFromFiles( ...
    soundFolder, annot.t0, annot.tEnd, newRate=targetRate);

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
    if ~isempty(params.nfft)
        nfft = params.nfft;
    else
        nfft = 2^nextpow2(floor(annot.duration / params.nSlices / overlap * sampleRate));
    end
    if ~isempty(params.nOverlap)
        nOverlap = params.nOverlap;
    else
        nOverlap = floor(nfft * overlap);
    end
    % Store resolved values back so they are available for output/logging.
    params.nfft    = nfft;
    params.nOverlap = nOverlap;
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
    noise.t0, noise.tEnd, exclusions=excludeTimes, channel=noise.channel, ...
    newRate=targetRate);

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

sigFilt         = [];
noiseFilt       = [];
ridgeFreq       = [];
quantileThresh  = [];
psdCells        = [];
histogramData   = [];
spectrogramData = [];
slicesData      = [];
ridgeData       = [];

switch params.snrType
    case 'spectrogram'
        [rmsSignal, rmsNoise, noiseVar, spectrogramData] = snrSpectrogram( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata);

    case 'spectrogramSlices'
        [rmsSignal, rmsNoise, noiseVar, slicesData] = snrSpectrogramSlices( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata);

    case 'quantiles'
        [rmsSignal, rmsNoise, noiseVar, quantileThresh, psdCells] = snrQuantiles( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, params.metadata);

    case 'nist'
        [rmsSignal, rmsNoise, noiseVar, histogramData] = snrHistogram( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, params.metadata);

    case 'timeDomain'
        [rmsSignal, rmsNoise, noiseVar, sigFilt, noiseFilt] = ...
            snrTimeDomain(annot.audio, noise.audio, freq, sampleRate, params.metadata);

    case 'ridge'
        [rmsSignal, rmsNoise, noiseVar, ridgeFreq, ~, ridgeData] = snrRidge( ...
            annot.audio, noise.audio, nfft, nOverlap, sampleRate, freq, ...
            params.metadata, params.ridgeParams);

    case 'synchrosqueeze'
        [rmsSignal, rmsNoise, noiseVar, ridgeFreq, ~, ridgeData] = snrSynchrosqueeze( ...
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
    % Lurton (2010, eq. 6.26): SNR as a function of the difference between
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
    levelUnit = 'dBFS';
    if ~isempty(params.metadata), levelUnit = 'dB re 1µPa'; end

    % Gather all method data into one struct for resolveDisplayType
    methodData.spectrogramData  = spectrogramData;
    methodData.sigSlicePowers   = sliceDataSig(spectrogramData, slicesData, ridgeData);
    methodData.noiseSlicePowers = sliceDataNoise(spectrogramData, slicesData, ridgeData);
    methodData.sigFilt          = sigFilt;
    methodData.histogramData    = histogramData;
    methodData.psdCells         = psdCells;

    displayType = resolveDisplayType(params, params.snrType, methodData);

    % Build plotParams once — provides pre/post/yLims for all display types,
    % not just the spectrogram case.
    plotParams = buildPlotParams(params, annot, sampleRate, freq, nfft);

    switch displayType
        case 'spectrogram'
            plotParams.snrType = params.snrType;
            if ~isempty(ridgeFreq),    plotParams.ridgeFreq      = ridgeFreq;       end
            if params.useLurton,       plotParams.noiseVar        = noiseVar;        end
            if ~isempty(quantileThresh), plotParams.quantileThresh = quantileThresh; end
            if ~isempty(psdCells),     plotParams.psdCells        = psdCells;        end
            if ~isempty(excludeTimes), plotParams.excludeTimes    = excludeTimes;    end
            if ~isempty(params.removeClicks)
                plotParams.removeClicks = params.removeClicks;
            end
            if strcmpi(params.snrType, 'nist') && isfield(histogramData, 'binCentres')
                plotParams.nistThresh = [rmsNoise / diff(freq), rmsSignal / diff(freq)];
            end
            spectroAnnotationAndNoise(annot, noise, soundFolder, plotParams, snr, ...
                params.metadata);

        case 'timeSeries'
            if ~isempty(sigFilt)
                % timeDomain method: per-sample FIR-filtered power
                clipT0    = noise.t0 - plotParams.pre  / 86400;
                clipTEnd  = max([annot.tEnd, noise.tEnd]) + plotParams.post / 86400;
                clipAudio = getAudioFromFiles(soundFolder, clipT0, clipTEnd, ...
                    channel=annot.channel, newRate=sampleRate);
                plotBandSamplePower(clipAudio, clipT0, annot, noise, ...
                    freq, sampleRate, rmsSignal, rmsNoise, noiseVar);
            else
                % All other methods: per-slice band power time series
                plotBandSlicePower(methodData.sigSlicePowers, ...
                    methodData.noiseSlicePowers, annot, noise, snr, levelUnit);
            end

        case 'histogram'
            switch lower(params.snrType)
                case 'nist'
                    plotHistogramSNR(histogramData, snr, ...
                        annot.rmsLevel, noise.rmsLevel, levelUnit);
                case 'quantiles'
                    fprintf('DEBUG quantiles histogram: psdCells n=%d min=%.3e q15=%.3e q85=%.3e\n', ...
                        numel(psdCells), min(psdCells), quantile(psdCells,0.15), quantileThresh);
                    plotQuantilesHistogram(psdCells, quantileThresh, snr, ...
                        annot.rmsLevel, noise.rmsLevel, levelUnit);
                otherwise
                    % All other methods: unified slice-power histogram
                    plotBandHistogram(methodData.sigSlicePowers, ...
                        methodData.noiseSlicePowers, snr, ...
                        rmsSignal, rmsNoise, noiseVar, levelUnit, params.useLurton);
            end
    end

    if params.pauseAfterPlot
        pause;
    end
end

end % processOne

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function v = sliceDataSig(spectrogramData, slicesData, ridgeData)
% Extract signal slice powers from whichever method data struct is populated.
if ~isempty(spectrogramData) && isstruct(spectrogramData) && isfield(spectrogramData, 'signalSlicePowers')
    v = spectrogramData.signalSlicePowers;
elseif ~isempty(slicesData) && isstruct(slicesData) && isfield(slicesData, 'sigSlicePowers')
    v = slicesData.sigSlicePowers;
elseif ~isempty(ridgeData) && isstruct(ridgeData) && isfield(ridgeData, 'sigSlicePowers')
    v = ridgeData.sigSlicePowers;
else
    v = [];
end
end

function v = sliceDataNoise(spectrogramData, slicesData, ridgeData)
% Extract noise slice powers from whichever method data struct is populated.
if ~isempty(spectrogramData) && isstruct(spectrogramData) && isfield(spectrogramData, 'noiseSlicePowers')
    v = spectrogramData.noiseSlicePowers;
elseif ~isempty(slicesData) && isstruct(slicesData) && isfield(slicesData, 'noiseSlicePowers')
    v = slicesData.noiseSlicePowers;
elseif ~isempty(ridgeData) && isstruct(ridgeData) && isfield(ridgeData, 'noiseSlicePowers')
    v = ridgeData.noiseSlicePowers;
else
    v = [];
end
end

function params = applyParamDefaults(params)

if ~isfield(params, 'parallelThreshold') || isempty(params.parallelThreshold)
    params.parallelThreshold = 100;
end
if ~isfield(params, 'verbose') || isempty(params.verbose)
    params.verbose = true;   % set false to suppress progress output
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
if ~isfield(params, 'resampleRate') || isempty(params.resampleRate)
    params.resampleRate = [];   % empty = use native rate
end
if ~isfield(params, 'nfft') || isempty(params.nfft)
    params.nfft = [];       % empty = derive from nSlices
end
if ~isfield(params, 'nOverlap') || isempty(params.nOverlap)
    params.nOverlap = [];   % empty = floor(nfft * 0.75)
end
if ~isfield(params, 'nSlices') || isempty(params.nSlices)
    params.nSlices = 30;
end
if ~isfield(params, 'displayType')
    params.displayType = [];   % empty = use per-method default
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

function plotParams = buildPlotParams(params, annot, sampleRate, freq, computedNfft)
% Build display parameters for spectroAnnotationAndNoise.
%
% win and overlap are ALWAYS derived from computedNfft so the displayed
% spectrogram uses the same window as the SNR computation.  Any win/overlap
% in params.plotParams are silently ignored — allowing them would produce
% a display that misrepresents the measurement.
%
% The caller may supply params.plotParams to control display-only fields:
%   .yLims   [loHz hiHz]  frequency axis range
%   .pre     seconds      clip buffer before noise window
%   .post    seconds      clip buffer after signal window

overlapPercent = 0.75;
if nargin >= 5 && ~isempty(computedNfft)
    win = computedNfft;
else
    win = floor(sampleRate / 4);
end

% Start with defaults, then let caller override display-only fields.
nyquist = sampleRate / 2;
yLo = max(0,       freq(1) - 0.5 * diff(freq));
yHi = min(nyquist, freq(2) + 0.5 * diff(freq));

plotParams.pre    = 1;
plotParams.post   = 1;
plotParams.yLims  = [yLo yHi];
plotParams.win    = win;
plotParams.overlap = floor(win * overlapPercent);
plotParams.freq   = annot.freq;

% Apply user display overrides (yLims, pre, post only).
if isfield(params, 'plotParams') && ~isempty(params.plotParams)
    sp = params.plotParams;
    if isfield(sp, 'yLims'), plotParams.yLims = sp.yLims; end
    if isfield(sp, 'pre'),   plotParams.pre   = sp.pre;   end
    if isfield(sp, 'post'),  plotParams.post  = sp.post;  end
end

end

