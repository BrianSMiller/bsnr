function annotsTrimmed = trimAnnotation(annots, options)
% Trim annotation bounds to the central energy of each detection.
%
% For each annotation, loads the signal audio and computes a spectrogram.
% Leading/trailing time slices and edge frequency bins that fall below the
% energy percentile threshold are trimmed.
%
% Trimming is intended to standardise SNR estimates across analysts with
% different annotation box tightness. It is only meaningful when frequency
% bounds vary per-annotation; if freq is set (fixed band), frequency
% trimming is skipped.
%
% USAGE
%   annotsTrimmed = trimAnnotation(annots)
%   annotsTrimmed = trimAnnotation(annots, 'trimMethod', 'cumulative')
%   annotsTrimmed = trimAnnotation(annots, 'energyPercentile', 10, 'showPlot', true)
%
% INPUTS
%   annots               - Annotation table or struct array
%
% NAME-VALUE OPTIONS
%   freq                 - Fixed frequency band [lo hi] Hz. If set,
%                          frequency trimming is skipped. Default: []
%   nfft                 - FFT length in samples. Default: [] (derived from nSlices)
%   nOverlap             - FFT overlap in samples. Default: floor(nfft*0.75)
%   nSlices              - Target time slices for nfft derivation. Default: 30
%   noiseLocation        - Noise window placement. Default: 'beforeAndAfter'
%   noiseDelay           - Gap between signal and noise window (s). Default: 0.5
%   noiseDuration_s      - Noise window duration (s). Default: [] (match signal)
%   energyPercentile     - Trim threshold percentile for all edges. Default: 2.5
%                          (trims to central 95% of energy)
%   timePercentile       - Sets both time edges. Default: energyPercentile
%   freqPercentile       - Sets both freq edges. Default: energyPercentile
%   timeStartPercentile  - Leading time edge only. Default: timePercentile
%   timeEndPercentile    - Trailing time edge only. Default: timePercentile
%   freqLowPercentile    - Low freq edge only. Default: freqPercentile
%   freqHighPercentile   - High freq edge only. Default: freqPercentile
%   minSlices            - Minimum slices after time trim. Default: 5
%   minBandHz            - Minimum bandwidth after freq trim (Hz). Default: 1
%   trimMethod           - 'centroid' (default) or 'cumulative'
%                          'centroid'   expand symmetrically from energy centroid;
%                                       best for calls centred in the box.
%                          'cumulative' trim low-energy edges via cumulative sum;
%                                       better for asymmetric FM calls.
%   showPlot             - Show diagnostic plot. Default: false
%
% OUTPUTS
%   annotsTrimmed - Same type as annots with updated t0, tEnd, duration,
%                   freq fields and a trimApplied logical column/field.
%
% NOTE: Trimming uses raw (uncalibrated) power — calibration is not needed
% since trim is based on relative energy within the annotation window.
%
% See also snrEstimate, plotTrimDiagnostic

arguments
    annots
    options.freq                 double   = []
    options.nfft                 double   = []
    options.nOverlap             double   = []
    options.nSlices              double   = 30
    options.noiseLocation        char     = 'beforeAndAfter'
    options.noiseDelay           double   = 0.5
    options.noiseDuration_s      double   = []
    options.energyPercentile     double   = 2.5
    options.timePercentile       double   = NaN  % inherit from energyPercentile if not set
    options.freqPercentile       double   = NaN  % inherit from energyPercentile if not set
    options.timeStartPercentile  double   = NaN  % inherit from timePercentile if not set
    options.timeEndPercentile    double   = NaN  % inherit from timePercentile if not set
    options.freqLowPercentile    double   = NaN  % inherit from freqPercentile if not set
    options.freqHighPercentile   double   = NaN  % inherit from freqPercentile if not set
    options.minSlices            double   = 5
    options.minBandHz            double   = 1
    options.trimMethod           char     = 'centroid'
    options.showPlot             logical  = false
end

% Resolve sentinel-defaulted percentile hierarchy
if isnan(options.timePercentile),      options.timePercentile      = options.energyPercentile; end
if isnan(options.freqPercentile),      options.freqPercentile      = options.energyPercentile; end
if isnan(options.timeStartPercentile), options.timeStartPercentile = options.timePercentile;   end
if isnan(options.timeEndPercentile),   options.timeEndPercentile   = options.timePercentile;   end
if isnan(options.freqLowPercentile),   options.freqLowPercentile   = options.freqPercentile;   end
if isnan(options.freqHighPercentile),  options.freqHighPercentile  = options.freqPercentile;   end

% Alias options -> params for rest of function
params = options;

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
