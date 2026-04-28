function [rmsSignal, rmsNoise, noiseVar, methodData] = snrSynchrosqueeze( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata, params)
% Estimate signal and noise power using the Fourier synchrosqueezed transform.
%
% The synchrosqueezed transform (fsst) reassigns STFT coefficients to
% concentrate them on the instantaneous frequency ridge, producing sharper
% time-frequency localisation than a standard spectrogram. This makes it
% better suited to FM tonal calls (whistles, upcalls) where energy is
% spread across multiple spectrogram bins due to the moving instantaneous
% frequency.
%
% The method follows the same ridge-based power estimation as snrRidge:
%   1. Compute fsst of signal and noise within the frequency band
%   2. Subtract per-bin median of noise fsst (noise floor normalisation)
%   3. Use tfridge to find the dominant instantaneous frequency ridge
%   4. Signal power per slice = fsst magnitude at the ridge bin
%   5. Noise power per slice = mean fsst magnitude of off-ridge bins,
%      excluding a guard band around the ridge
%
% The key advantage over snrRidge is that fsst concentrates energy much
% more tightly onto the true instantaneous frequency, reducing spectral
% leakage and making the ridge easier to track at low SNR.
%
% Reference:
%   Thakur, G., Brevdo, E., Fuckar, N.S., & Wu, H.T. (2013). The
%   Synchrosqueezing algorithm for time-varying spectral analysis:
%   Robustness properties and new paleoclimate applications.
%   Signal Processing, 93(5), 1079-1094.
%   https://arxiv.org/abs/1105.0010
%
% The caller (snrEstimate) applies whichever SNR formula is requested.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples (column vector)
%   nfft        FFT length (samples) — controls frequency resolution
%   nOverlap    Window overlap (samples)
%   sampleRate  Sample rate in Hz
%   freq        [lowHz highHz] frequency band to search for the ridge
%   metadata    Calibration metadata struct, or [] for no calibration
%   params      Optional struct of method-specific parameters:
%                 .ridgePenalty  tfridge frequency-jump penalty (default 1)
%                 .guardBins        Bins either side of ridge excluded from
%                                   noise estimate (default 2)
%                 .ridgeSmoothSpan  LOESS span for ridge smoothing as fraction
%                                   of slices (default 0). Set > 0 to enable.
%                                   Only effective when annotation bounds are
%                                   tight (e.g. after trimAnnotation). With
%                                   loose bounds, smoothing may fit noise rather
%                                   than the signal and degrade results.
%                 .ridgeTrimPct     Fraction of lowest-energy slices to exclude
%                                   before smoothing (default 0.25). Only used
%                                   when ridgeSmoothSpan > 0.
%
% OUTPUTS
%   rmsSignal   Mean power at the ridge across time slices (linear)
%   rmsNoise    Mean off-ridge noise power across time slices (linear)
%   noiseVar    Variance of off-ridge noise power across slices
%   ridgeFreq   Estimated ridge frequency per time slice (Hz)
%   sliceSnrdB  Per-slice SNR in dB using simple power ratio (diagnostic)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parameters
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
    params.ridgeSmoothSpan = 0.3;
end
if ~isfield(params, 'ridgeTrimPct') || isempty(params.ridgeTrimPct)
    params.ridgeTrimPct = 0.25;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compute synchrosqueezed transform
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% fsst signature: [sst, f, t] = fsst(x, fs, window)
% The window length sets frequency resolution; overlap is always len(win)-1.
% We use the nfft parameter as the window length for consistency with other methods.
win = hann(nfft);

try
    [sigSst,  sF, sT] = fsst(sigAudio,   sampleRate, win);
    [noiseSst, ~,  ~] = fsst(noiseAudio, sampleRate, win);
catch me
    warning('snrSynchrosqueeze:fsstFailed', 'fsst failed: %s', me.message);
    [rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan);
    methodData = emptyRidgeData('synchrosqueeze');
    return
end

% fsst returns complex reassigned STFT coefficients.
% Normalise by window energy and sample rate to obtain PSD in the same
% units as spectrogram() — power per Hz per sample — making SNR values
% comparable across methods.
% spectrogram normalisation: PSD = |STFT|^2 / (fs * sum(win.^2))
winNorm  = sampleRate * sum(win.^2);
sigPsd   = abs(sigSst).^2  / winNorm;
noisePsd = abs(noiseSst).^2 / winNorm;

% Apply calibration if provided
if ~isempty(metadata)
    sigPsd   = applyCalibration(sigPsd,   sF, sT, metadata);
    noisePsd = applyCalibration(noisePsd, sF, sT, metadata);
end

% Restrict to frequency band
fIx      = sF >= freq(1) & sF <= freq(2);
sigBand  = sigPsd(fIx, :);
fBand    = sF(fIx);

if isempty(fBand) || size(sigBand, 1) < 3
    warning('snrSynchrosqueeze:bandTooNarrow', ...
        'Fewer than 3 frequency bins in [%.1f %.1f] Hz.', freq(1), freq(2));
    [rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan);
    methodData = emptyRidgeData('synchrosqueeze');
    return
end

% Cap guardBins so at least one noise bin is always available.
nBand = size(sigBand, 1);
params.guardBins = min(params.guardBins, floor((nBand - 1) / 2));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Noise floor normalisation and ridge tracking
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Subtract per-bin median of NOISE fsst (not signal) to flatten noise floor
% without removing a stationary signal's contribution
noiseBand    = noisePsd(fIx, :);
binMedian    = median(noiseBand, 2);
sigNorm      = sigBand - repmat(binMedian, 1, size(sigBand, 2));
sigNorm      = max(sigNorm, 0);

% Track ridge using bin indices as frequency axis
nBins        = size(sigNorm, 1);
binIdxVec    = (1:nBins)';
[ridgeVals, ~] = tfridge(sigNorm, binIdxVec, params.ridgePenalty, 'NumRidges', 1);
ridgeBinIdx  = max(1, min(nBins, round(ridgeVals(:))));
ridgeFreq    = fBand(ridgeBinIdx);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% LOESS smoothing of ridge track
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

nSlices = length(sT);

% Raw signal power at each ridge bin for energy trim
sigSliceRaw = arrayfun(@(i) sigBand(ridgeBinIdx(i), i), (1:nSlices)');

ridgeFreqSmooth = ridgeFreq;
ridgeCoreIdx    = true(nSlices, 1);

if params.ridgeSmoothSpan > 0 && nSlices >= 5
    trimThresh = prctile(sigSliceRaw, params.ridgeTrimPct * 100);
    coreIdx    = find(sigSliceRaw >= trimThresh);
    if numel(coreIdx) >= 4
        ridgeCoreIdx(:)       = false;
        ridgeCoreIdx(coreIdx) = true;
        try
            ridgeSmoothed   = smooth(coreIdx, ridgeFreq(coreIdx), ...
                params.ridgeSmoothSpan, 'loess');
            ridgeFreqSmooth = interp1(coreIdx, ridgeSmoothed, ...
                (1:nSlices)', 'linear', 'extrap');
            ridgeFreqSmooth = max(freq(1), min(freq(2), ridgeFreqSmooth));
        catch
            winLen = max(3, round(params.ridgeSmoothSpan * nSlices));
            ridgeFreqSmooth = movmean(ridgeFreq, winLen, 'omitnan');
        end
    end
end

% Convert smoothed frequencies to bin indices
ridgeBinIdxSmooth = arrayfun(@(f) ...
    max(1, min(nBand, round(interp1(fBand, 1:numel(fBand), f, 'linear', 'extrap')))), ...
    ridgeFreqSmooth);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Per-slice signal and noise power
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% For the signal: measure power at the smoothed ridge bin per time slice.
% For the noise: use a single per-bin mean across all noise slices.
nSlices  = length(sT);
sigSlice = nan(nSlices, 1);

% Pre-compute per-bin mean and variance of noise across all its slices
noiseBinMean = mean(noiseBand, 2);   % nBins x 1
noiseBinVar  = var(noiseBand,  0, 2); % nBins x 1

noiseSlice = nan(nSlices, 1);
noiseVarSlice = nan(nSlices, 1);

for i = 1:nSlices
    rb = ridgeBinIdxSmooth(i);   % smoothed ridge
    sigSlice(i) = sigBand(rb, i);

    guardLo = max(1,     rb - params.guardBins);
    guardHi = min(nBins, rb + params.guardBins);
    noiseIx = true(nBins, 1);
    noiseIx(guardLo:guardHi) = false;
    if any(noiseIx)
        noiseSlice(i)    = mean(noiseBinMean(noiseIx));
        noiseVarSlice(i) = mean(noiseBinVar(noiseIx));
    end
end

rmsSignal  = mean(sigSlice,      'omitnan');
rmsNoise   = mean(noiseSlice,    'omitnan');
noiseVar   = mean(noiseVarSlice, 'omitnan');

methodData.method           = 'synchrosqueeze';
methodData.ridgeFreq        = ridgeFreq;
methodData.ridgeFreqSmooth  = ridgeFreqSmooth;
methodData.ridgeCoreIdx     = ridgeCoreIdx;
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

