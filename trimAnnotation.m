function annotsTrimmed = trimAnnotation(annots, params)
% Trim annotation bounds to the central energy of each detection.
%
% For each annotation, loads the signal audio and computes a spectrogram.
% Leading/trailing time slices and edge frequency bins that fall below the
% energy percentile threshold are trimmed. The same trim is applied to the
% noise window bounds.
%
% Trimming is intended to standardise SNR estimates across analysts with
% different annotation box tightness. It is only meaningful when frequency
% bounds vary per-annotation; if params.freq is set (fixed band), frequency
% trimming is skipped.
%
% INPUTS
%   annots  - Annotation table or struct array (same format as snrEstimate)
%   params  - Parameter struct (shared with snrEstimate). Relevant fields:
%               .freq             Fixed frequency band [lo hi] Hz. If set,
%                                 frequency trimming is skipped.
%               .nfft             FFT length in samples. If empty, derived
%                                 per-annotation from nSlices.
%               .nOverlap         FFT overlap in samples. Default: floor(nfft*0.75)
%               .nSlices          Target slices for nfft derivation. Default: 30
%               .noiseLocation    Noise placement (default: 'beforeAndAfter')
%               .noiseDelay       Gap in seconds (default: 0.5)
%               .noiseDuration_s  Noise window duration in seconds.
%                                 Default: [] (match annotation duration)
%               .energyPercentile Trim threshold percentile. Default: 2.5
%                                 Applied to all edges unless overridden.
%               .timePercentile   Sets both time edges. Default: energyPercentile
%               .freqPercentile   Sets both freq edges. Default: energyPercentile
%               .timeStartPercentile  Leading time edge. Default: timePercentile
%               .timeEndPercentile    Trailing time edge. Default: timePercentile
%               .freqLowPercentile    Low freq edge. Default: freqPercentile
%               .freqHighPercentile   High freq edge. Default: freqPercentile
%               .minSlices        Minimum slices after time trim. Default: 5
%               .minBandHz        Minimum bandwidth after freq trim (Hz).
%                                 Default: 1 Hz. If trimmed band is narrower,
%                                 freq trim is skipped for that annotation.
%               .trimMethod       Trimming method for both time and frequency.
%                                 Default: 'centroid'
%                                 'centroid' — expand symmetrically outward from
%                                   the energy centroid. Best for calls centred
%                                   within the annotation box (most common case).
%                                 'cumulative' — trim low-energy edges using
%                                   forward cumulative sum. Better for asymmetric
%                                   calls (e.g. FM sweeps with one-sided buffers).
%               .showPlot         Show diagnostic plot. Default: false
%
% OUTPUTS
%   annotsTrimmed - Annotation table with updated t0, tEnd, duration, freq
%                   columns. A 'trimApplied' logical column is added.
%
% NOTE: Trimming operates on raw (uncalibrated) power. Calibration is not
% needed since trimming is based on relative energy within the annotation.
%
% See also snrEstimate, plotTrimDiagnostic

if nargin < 2 || isempty(params)
    params = struct();
end

% Apply defaults shared with snrEstimate
if ~isfield(params, 'freq')          || isempty(params.freq),          params.freq          = []; end
if ~isfield(params, 'nfft')          || isempty(params.nfft),          params.nfft          = []; end
if ~isfield(params, 'nOverlap')      || isempty(params.nOverlap),      params.nOverlap      = []; end
if ~isfield(params, 'nSlices')       || isempty(params.nSlices),       params.nSlices       = 30; end
if ~isfield(params, 'noiseLocation') || isempty(params.noiseLocation), params.noiseLocation = 'beforeAndAfter'; end
if ~isfield(params, 'noiseDelay')    || isempty(params.noiseDelay),    params.noiseDelay    = 0.5; end
if ~isfield(params, 'noiseDuration_s'),                                params.noiseDuration_s = []; end
if ~isfield(params, 'energyPercentile') || isempty(params.energyPercentile), params.energyPercentile = 2.5; end
% Per-axis percentiles override energyPercentile if set.
% timePercentile/freqPercentile set both ends; per-edge params override further.
if ~isfield(params, 'timePercentile')      || isempty(params.timePercentile),      params.timePercentile      = params.energyPercentile; end
if ~isfield(params, 'freqPercentile')      || isempty(params.freqPercentile),      params.freqPercentile      = params.energyPercentile; end
if ~isfield(params, 'timeStartPercentile') || isempty(params.timeStartPercentile), params.timeStartPercentile = params.timePercentile; end
if ~isfield(params, 'timeEndPercentile')   || isempty(params.timeEndPercentile),   params.timeEndPercentile   = params.timePercentile; end
if ~isfield(params, 'freqLowPercentile')   || isempty(params.freqLowPercentile),   params.freqLowPercentile   = params.freqPercentile; end
if ~isfield(params, 'freqHighPercentile')  || isempty(params.freqHighPercentile),  params.freqHighPercentile  = params.freqPercentile; end
if ~isfield(params, 'minSlices')     || isempty(params.minSlices),     params.minSlices     = 5; end
if ~isfield(params, 'minBandHz')     || isempty(params.minBandHz),     params.minBandHz     = 1; end
if ~isfield(params, 'showPlot')      || isempty(params.showPlot),      params.showPlot      = false; end
if ~isfield(params, 'trimMethod')    || isempty(params.trimMethod),    params.trimMethod    = 'centroid'; end

fixedFreq = ~isempty(params.freq);

% Convert table to struct array if needed
if istable(annots)
    annotStruct = table2struct(annots);
    wasTable = true;
else
    annotStruct = annots;
    wasTable = false;
end
nAnnot = numel(annotStruct);

% Pre-allocate output fields
t0New       = [annotStruct.t0]';
tEndNew     = [annotStruct.tEnd]';
durNew      = [annotStruct.duration]';
freqNew     = reshape([annotStruct.freq], 2, nAnnot)';
trimApplied = false(nAnnot, 1);

for i = 1:nAnnot
    annot = annotStruct(i);

    % Unwrap cell fields from table2struct
    if iscell(annot.soundFolder), annot.soundFolder = annot.soundFolder{1}; end
    if iscell(annot.t0),          annot.t0          = annot.t0{1};          end
    if iscell(annot.tEnd),        annot.tEnd        = annot.tEnd{1};        end
    if iscell(annot.freq),        annot.freq        = annot.freq{1};        end

    % Convert datetime to datenum
    if isdatetime(annot.t0)
        annot.t0   = datenum(annot.t0);
        annot.tEnd = datenum(annot.tEnd);
    end

    if ~isfield(annot,'duration') || ~isfinite(annot.duration)
        annot.duration = (annot.tEnd - annot.t0) * 86400;
    end

    % Frequency band for this annotation
    if fixedFreq
        freq = params.freq;
    else
        freq = annot.freq;
    end

    % nfft resolved after loading audio (sampleRate needed)
    % Placeholder — actual nfft set below after wavFolderInfo call
    nfft     = params.nfft;
    nOverlap = params.nOverlap;

    try
        %% Load signal audio
        sf = wavFolderInfo(annot.soundFolder, '', false, false);
        sampleRate = sf(1).sampleRate;

        % Resolve nfft now that sampleRate is known
        overlap = 0.75;
        if ~isempty(nfft)
            if isempty(nOverlap)
                nOverlap = floor(nfft * overlap);
            end
        else
            nfft     = 2^nextpow2(floor(annot.duration / params.nSlices / overlap * sampleRate));
            nOverlap = floor(nfft * overlap);
        end

        [sigAudio, ~, ~] = getAudioFromFiles(sf, annot.t0, annot.tEnd);
        if isempty(sigAudio) || length(sigAudio) < nfft
            continue
        end

        %% Build signal spectrogram
        [~, f, t, psd] = spectrogram(sigAudio, nfft, nOverlap, nfft, sampleRate);

        % Band mask
        fMask = f >= freq(1) & f <= freq(2);
        if sum(fMask) < 2, continue; end

        psdBand = psd(fMask, :);   % [nFreqBins x nSlices]

        %% Time trim — cumulative energy across slices
        sliceEnergy  = sum(psdBand, 1);                     % [1 x nSlices]
        cumFwd       = cumsum(sliceEnergy);
        totalEnergy  = cumFwd(end);
        if strcmp(params.trimMethod, 'centroid')
            % Centroid-based symmetric time trim
            centroidSlice = round(sum((1:numel(sliceEnergy)) .* sliceEnergy) / totalEnergy);
            centroidSlice = max(1, min(numel(sliceEnergy), centroidSlice));
            firstSlice = centroidSlice;
            lastSlice  = centroidSlice;
            tStartPct  = (params.timeStartPercentile + params.timeEndPercentile) / 2;
            while true
                if sum(sliceEnergy(firstSlice:lastSlice)) / totalEnergy >= (1 - 2*tStartPct/100)
                    break;
                end
                canLow  = firstSlice > 1;
                canHigh = lastSlice  < numel(sliceEnergy);
                if ~canLow && ~canHigh, break; end
                if canLow,  lowE  = sliceEnergy(firstSlice - 1); else, lowE  = 0; end
                if canHigh, highE = sliceEnergy(lastSlice  + 1); else, highE = 0; end
                if lowE >= highE && canLow
                    firstSlice = firstSlice - 1;
                elseif canHigh
                    lastSlice = lastSlice + 1;
                else
                    firstSlice = firstSlice - 1;
                end
            end
        else
            % Cumulative time trim
            threshStart  = params.timeStartPercentile / 100 * totalEnergy;
            threshEnd    = params.timeEndPercentile   / 100 * totalEnergy;
            firstSlice   = find(cumFwd >= threshStart,              1, 'first');
            lastSlice    = find(cumFwd >= totalEnergy - threshEnd,  1, 'first');
        end

        % Enforce minimum slices
        if isempty(firstSlice), firstSlice = 1; end
        if isempty(lastSlice),  lastSlice  = numel(sliceEnergy); end
        if (lastSlice - firstSlice + 1) < params.minSlices
            firstSlice = 1;
            lastSlice  = numel(sliceEnergy);
        end

        % Convert slice indices to time offsets
        tSlices       = t;
        t0Offset      = tSlices(firstSlice);
        tEndOffset    = tSlices(lastSlice);
        newT0         = annot.t0   + t0Offset / 86400;
        newTEnd       = annot.tEnd - (t(end) - tEndOffset) / 86400;
        newDur        = (newTEnd - newT0) * 86400;

        %% Frequency trim (only when using per-annotation bounds)
        % Operates on the time-trimmed PSD so silent margins don't
        % contaminate the frequency energy profile.
        newFreq = freq;
        if ~fixedFreq
            psdTrimmed  = psdBand(:, firstSlice:lastSlice);   % time-trimmed
            binEnergy   = sum(psdTrimmed, 2);                  % [nFreqBins x 1]
            totalFE     = sum(binEnergy);

            fThreshLow  = params.freqLowPercentile  / 100 * totalFE;
            fThreshHigh = params.freqHighPercentile / 100 * totalFE;
            if strcmp(params.trimMethod, 'centroid')
                % Centroid-based symmetric expansion:
                % grow outward from energy centroid until band captures
                % central (1 - 2*percentile)% of energy. Produces
                % symmetric bounds for symmetric call spectra.
                centroidBin = round(sum((1:numel(binEnergy))' .* binEnergy) / totalFE);
                centroidBin = max(1, min(numel(binEnergy), centroidBin));
                firstBin = centroidBin;
                lastBin  = centroidBin;
                while true
                    if sum(binEnergy(firstBin:lastBin)) / totalFE >= (1 - (params.freqLowPercentile + params.freqHighPercentile)/100)
                        break;
                    end
                    canLow  = firstBin > 1;
                    canHigh = lastBin  < numel(binEnergy);
                    if ~canLow && ~canHigh, break; end
                    if canLow,  lowE  = binEnergy(firstBin - 1); else, lowE  = 0; end
                    if canHigh, highE = binEnergy(lastBin  + 1); else, highE = 0; end
                    if lowE >= highE && canLow
                        firstBin = firstBin - 1;
                    elseif canHigh
                        lastBin = lastBin + 1;
                    else
                        firstBin = firstBin - 1;
                    end
                end
            else
                % Cumulative (default): trim low-energy edges using
                % forward cumulative sum. May be asymmetric if call
                % energy is not centred in the annotation band.
                cumFreqFwd = cumsum(binEnergy);
                firstBin   = find(cumFreqFwd >= fThreshLow,            1, 'first');
                lastBin    = find(cumFreqFwd >= totalFE - fThreshHigh, 1, 'first');
                if isempty(firstBin), firstBin = 1; end
                if isempty(lastBin),  lastBin  = numel(binEnergy); end
            end

            fBand       = f(fMask);
            trimmedBand = fBand(lastBin) - fBand(firstBin);
            if trimmedBand >= params.minBandHz
                newFreq = [fBand(firstBin), fBand(lastBin)];
            end
        end

        %% Store trimmed bounds
        t0New(i)       = newT0;
        tEndNew(i)     = newTEnd;
        durNew(i)      = newDur;
        freqNew(i,:)   = newFreq;
        trimApplied(i) = true;

        %% Update noise window bounds
        % Noise is placed relative to trimmed signal bounds.
        % Noise duration matches trimmed signal duration unless explicitly set.
        if ~isempty(params.noiseDuration_s)
            noiseDur = params.noiseDuration_s;
        else
            noiseDur = newDur;
        end

        %% Optional diagnostic plot
        if params.showPlot
            % Quick SNR from audio already in memory — use margins as noise
            nSig     = length(sigAudio);
            idx1     = max(1,    round(t(firstSlice)*sampleRate));
            idx2     = min(nSig, round(t(lastSlice) *sampleRate)+1);
            noiseAudio = [sigAudio(1:idx1); sigAudio(idx2:nSig)];
            if length(noiseAudio) < nfft, noiseAudio = sigAudio; end
            [rmsS, rmsN] = snrSpectrogramSlices(sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, []);
            snrBefore = 10*log10(rmsS / rmsN);
            trimIdx1  = max(1,    round(t(firstSlice)*sampleRate)+1);
            trimIdx2  = min(nSig, round(t(lastSlice) *sampleRate));
            trimAudio = sigAudio(trimIdx1:trimIdx2);
            if length(trimAudio) >= nfft
                [rmsS2, rmsN2] = snrSpectrogramSlices(trimAudio, noiseAudio, nfft, nOverlap, sampleRate, newFreq, []);
                snrAfter = 10*log10(rmsS2 / rmsN2);
            else
                snrAfter = [];
            end
            plotTrimDiagnostic(sigAudio, psd, f, t, freq, newFreq, ...
                firstSlice, lastSlice, fMask, firstBin, lastBin, ...
                annot, newT0, newTEnd, sampleRate, nfft, nOverlap, fixedFreq, ...
                snrBefore, snrAfter);
        end

    catch
        % On any error, leave annotation unchanged
        continue
    end
end

%% Rebuild output as same type as input
if wasTable
    annotsTrimmed = annots;
    annotsTrimmed.t0       = t0New;
    annotsTrimmed.tEnd     = tEndNew;
    annotsTrimmed.duration = durNew;
    annotsTrimmed.freq     = freqNew;
    annotsTrimmed.trimApplied = trimApplied;
else
    annotsTrimmed = annotStruct;
    for i = 1:nAnnot
        annotsTrimmed(i).t0          = t0New(i);
        annotsTrimmed(i).tEnd        = tEndNew(i);
        annotsTrimmed(i).duration    = durNew(i);
        annotsTrimmed(i).freq        = freqNew(i,:);
        annotsTrimmed(i).trimApplied = trimApplied(i);
    end
end

end
