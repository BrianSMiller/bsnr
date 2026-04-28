function [rmsSignal, rmsNoise, noiseVar, methodData] = snrRidge( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata, params)
% Estimate signal and noise power by tracking the spectral ridge of a tonal call.
%
% Computes a spectrogram, normalises each frequency bin by its median power
% across time (to flatten the noise floor), then uses tfridge to find the
% dominant frequency ridge within the specified band. Signal power per time
% slice is taken from the un-normalised spectrogram at the ridge bin;
% noise power per slice is the mean of off-ridge bins within the band,
% excluding a guard band around the ridge to avoid spectral leakage bias.
%
% This approach is inspired by the signal processing front-end described in:
%   Roch et al. (2011) "Automated extraction of odontocete whistle contours"
%   J. Acoust. Soc. Am. 130(4), 2212-2223. https://doi.org/10.1121/1.3624821
%
% Compared to snrSpectrogram (which averages all in-band bins equally), this
% method is better suited to tonal calls because:
%   - The ridge tracker is robust to short dropouts and transient interference
%     (tfridge penalises large inter-slice frequency jumps)
%   - Per-bin median subtraction normalises the noise floor before tracking,
%     preventing the ridge from being pulled toward noisier frequency regions
%   - Only the ridge bin contributes to signal power, avoiding dilution by
%     off-signal bins
%
% The caller (snrEstimate) applies whichever SNR formula is requested.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples (column vector)
%   nfft        FFT length (samples)
%   nOverlap    Window overlap (samples)
%   sampleRate  Sample rate in Hz
%   freq        [lowHz highHz] frequency band to search for the ridge
%   metadata    Calibration metadata struct, or [] for no calibration
%   params      Optional struct of ridge-specific parameters:
%                 .ridgePenalty  tfridge frequency-jump penalty (default 1).
%                                Increase to force a smoother ridge; decrease
%                                to allow faster frequency modulation.
%                 .guardBins        Number of FFT bins either side of the ridge
%                                   to exclude from the noise estimate (default 2).
%                 .ridgeSmoothSpan  LOESS span for ridge smoothing as fraction of
%                                   slices (default 0). Set > 0 to enable.
%                                   Only effective when annotation bounds are tight
%                                   (e.g. after trimAnnotation). With loose bounds,
%                                   smoothing may fit the noise rather than the
%                                   signal and degrade results.
%                                   Recommended workflow:
%                                     annotTrimmed = trimAnnotation(annots);
%                                     p.ridgeParams.ridgeSmoothSpan = 0.3;
%                                     result = snrEstimate(annotTrimmed, p);
%                 .ridgeTrimPct     Fraction of lowest-energy slices to exclude
%                                   before smoothing (default 0.25). Only used
%                                   when ridgeSmoothSpan > 0.
%
% OUTPUTS
%   rmsSignal   Mean power at the ridge across time slices (linear)
%   rmsNoise    Mean off-ridge noise power across time slices (linear)
%   noiseVar    Variance of off-ridge noise power across slices
%   ridgeFreq   Estimated ridge frequency per time slice (Hz), length = nSlices
%   sliceSnrdB  Per-slice SNR in dB using simple power ratio (for diagnostics)
%
% NOTE
%   ridgeFreq and sliceSnrdB are diagnostic outputs. For the primary SNR
%   value, use the formula applied by snrEstimate (simple or Lurton).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parse ridge-specific parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if nargin < 8 || isempty(params)
    params = struct();
end
if ~isfield(params, 'ridgePenalty') || isempty(params.ridgePenalty)
    params.ridgePenalty = 1;
end
if ~isfield(params, 'guardBins') || isempty(params.guardBins)
    params.guardBins = 2;
end
if ~isfield(params, 'ridgeSmoothSpan') || isempty(params.ridgeSmoothSpan)
    params.ridgeSmoothSpan = 0;    % LOESS smoothing disabled by default; enable after trimAnnotation
end
if ~isfield(params, 'ridgeTrimPct') || isempty(params.ridgeTrimPct)
    params.ridgeTrimPct = 0.25;    % trim bottom fraction of slice powers before smoothing
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compute spectrogram and apply calibration
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[sigPsd,  sF, sT] = computeSpectrogram(sigAudio,   nfft, nOverlap, sampleRate);
[noisePsd, ~,  ~] = computeSpectrogram(noiseAudio,  nfft, nOverlap, sampleRate);

if ~isempty(metadata)
    sigPsd   = applyCalibration(sigPsd,   sF, sT, metadata);
    noisePsd = applyCalibration(noisePsd, sF, sT, metadata);
end

% Restrict to the requested frequency band
fIx     = sF >= freq(1) & sF <= freq(2);
sigBand = sigPsd(fIx, :);
fBand   = sF(fIx);

if isempty(fBand) || size(sigBand, 1) < 3
    warning('snrRidge:bandTooNarrow', ...
        'Fewer than 3 FFT bins in [%.1f %.1f] Hz — cannot track ridge.', ...
        freq(1), freq(2));
    [rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan);
    methodData = emptyRidgeData('ridge');
    return
end

% Cap guardBins so there is always at least one noise bin available.
% With a narrow band (e.g. 4 bins), the default guardBins=2 would exclude
% all non-ridge bins for central ridge positions, giving NaN noise estimates.
nBand = size(sigBand, 1);
params.guardBins = min(params.guardBins, floor((nBand - 1) / 2));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Per-bin median subtraction (noise floor normalisation)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Subtract the per-bin median of the NOISE spectrogram from the signal
% spectrogram. Using the noise median (rather than the signal's own median)
% avoids removing a stationary tone whose median IS the tone — which would
% flatten the very signal tfridge needs to track.
% Normalisation is applied only for ridge finding; power is measured from
% the un-normalised sigBand below.

noiseBandForNorm = noisePsd(fIx, :);
binMedian        = median(noiseBandForNorm, 2);  % noise floor per freq bin
sigNorm          = sigBand - repmat(binMedian, 1, size(sigBand, 2));
sigNorm          = max(sigNorm, 0);              % clip negative residuals

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Ridge tracking with tfridge
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% tfridge works on the normalised in-band PSD.
% Call without a frequency vector so it returns integer bin indices.
% penalty penalises inter-slice frequency jumps in units of bins.
% Pass bin indices (1:nBins) as the frequency vector. tfridge then
% returns those same values, which we use directly as integer indices.
% Penalty penalises inter-slice jumps in units of bins.
nBins       = size(sigNorm, 1);
binIdxVec   = (1:nBins)';
[ridgeVals, ~] = tfridge(sigNorm, binIdxVec, params.ridgePenalty, ...
    'NumRidges', 1);
ridgeBinIdx = round(ridgeVals(:));          % integer bin indices
ridgeBinIdx = max(1, min(nBins, ridgeBinIdx)); % clamp to valid range
ridgeFreq   = fBand(ridgeBinIdx);           % convert to Hz

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% LOESS smoothing of ridge track
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Two-step: (1) energy-based trim to find core slices where the call is
% strongest, (2) LOESS smooth fitted to core only, interpolated to full
% length. This reduces noise-driven ridge wandering at annotation edges,
% which is common at low SNR.

nSlices = length(sT);
nBand   = size(sigBand, 1);

% Compute raw signal power at each ridge bin (for trim threshold)
sigSliceRaw = arrayfun(@(i) sigBand(ridgeBinIdx(i), i), (1:nSlices)');

ridgeFreqSmooth = ridgeFreq;   % default: no smoothing
ridgeCoreIdx    = true(nSlices, 1);

if params.ridgeSmoothSpan > 0 && nSlices >= 5
    % Energy trim: keep slices above ridgeTrimPct percentile of raw power
    trimThresh   = prctile(sigSliceRaw, params.ridgeTrimPct * 100);
    coreIdx      = find(sigSliceRaw >= trimThresh);
    if numel(coreIdx) >= 4
        ridgeCoreIdx(:)      = false;
        ridgeCoreIdx(coreIdx) = true;

        % LOESS smooth on core slice indices
        % smooth() requires the Statistics and Machine Learning Toolbox;
        % fall back to movmean if unavailable.
        try
            ridgeFreqCore   = ridgeFreq(coreIdx);
            ridgeSmoothed   = smooth(coreIdx, ridgeFreqCore, ...
                params.ridgeSmoothSpan, 'loess');
            % Interpolate smoothed core back to all slices
            ridgeFreqSmooth = interp1(coreIdx, ridgeSmoothed, ...
                (1:nSlices)', 'linear', 'extrap');
            % Clamp to band limits
            ridgeFreqSmooth = max(freq(1), min(freq(2), ridgeFreqSmooth));
        catch
            % smooth() unavailable — fall back to moving average
            winLen = max(3, round(params.ridgeSmoothSpan * nSlices));
            ridgeFreqSmooth = movmean(ridgeFreq, winLen, 'omitnan');
        end
    end
end

% Convert smoothed frequencies back to bin indices for power measurement
ridgeBinIdxSmooth = arrayfun(@(f) ...
    max(1, min(nBand, round(interp1(fBand, 1:numel(fBand), f, 'linear', 'extrap')))), ...
    ridgeFreqSmooth);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Per-slice signal and noise power from un-normalised spectrogram
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sigSlice     = nan(nSlices, 1);
noiseSlice   = nan(nSlices, 1);
noiseSliceN  = nan(nSlices, 1);

% Restrict the noise spectrogram to the same band and average over time
noiseBand = mean(noisePsd(fIx, :), 2);   % [nBand x 1]

for i = 1:nSlices
    rb = ridgeBinIdxSmooth(i);   % use smoothed ridge for power measurement

    % Signal: power at the ridge bin
    sigSlice(i) = sigBand(rb, i);

    % Noise: mean of off-ridge bins, excluding guard band
    guardLo  = max(1,     rb - params.guardBins);
    guardHi  = min(nBand, rb + params.guardBins);
    noiseIx  = true(nBand, 1);
    noiseIx(guardLo:guardHi) = false;

    if any(noiseIx)
        noiseSlice(i)  = mean(noiseBand(noiseIx));
        noiseSliceN(i) = noiseSlice(i);
    end
end

% Aggregate across slices
rmsSignal  = mean(sigSlice,   'omitnan');
rmsNoise   = mean(noiseSlice, 'omitnan');
noiseVar   = var(noiseSliceN(~isnan(noiseSliceN)));

% Build methodData
methodData.method           = 'ridge';
methodData.ridgeFreq        = ridgeFreq;         % raw tfridge output
methodData.ridgeFreqSmooth  = ridgeFreqSmooth;   % LOESS-smoothed (used for power)
methodData.ridgeCoreIdx     = ridgeCoreIdx;      % core energy slices used for smoothing
methodData.sliceSnrdB       = 10 * log10(sigSlice ./ noiseSlice);
methodData.sigSlicePowers   = sigSlice;
methodData.noiseSlicePowers = noiseSlice;

end

function md = emptyRidgeData(method)
md.method           = method;
md.ridgeFreq        = nan(1);
md.ridgeFreqSmooth  = nan(1);
md.ridgeCoreIdx     = false(1);
md.sliceSnrdB       = nan(1);
md.sigSlicePowers   = [];
md.noiseSlicePowers = [];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [psd, sF, sT] = computeSpectrogram(x, window, nOverlap, sampleRate)

if length(x) < window
    window   = length(x);
    nOverlap = 0;
end
x = x - mean(x);

try
    [~, sF, sT, psd] = spectrogram(x, window, nOverlap, window, sampleRate);
catch
    psd = nan; sF = nan; sT = nan;
end

end

