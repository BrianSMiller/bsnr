function [rmsSignal, rmsNoise, noiseVar, ridgeFreq, sliceSnrdB] = snrRidge( ...
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
%                 .guardBins     Number of FFT bins either side of the ridge
%                                to exclude from the noise estimate (default 2).
%                                Prevents spectral leakage from inflating noise.
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
    [rmsSignal, rmsNoise, noiseVar, ridgeFreq, sliceSnrdB] = ...
        deal(nan, nan, nan, nan(size(sT)), nan(size(sT)));
    return
end

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
%% Per-slice signal and noise power from un-normalised spectrogram
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

nSlices      = length(sT);
nBand        = size(sigBand, 1);
sigSlice     = nan(nSlices, 1);
noiseSlice   = nan(nSlices, 1);
noiseSliceN  = nan(nSlices, 1);

% Restrict the noise spectrogram to the same band
noiseBand = noisePsd(fIx, :);

for i = 1:nSlices
    rb = ridgeBinIdx(i);

    % Signal: power at the ridge bin
    sigSlice(i) = sigBand(rb, i);

    % Noise: mean of off-ridge bins, excluding guard band
    guardLo  = max(1,     rb - params.guardBins);
    guardHi  = min(nBand, rb + params.guardBins);
    noiseIx  = true(nBand, 1);
    noiseIx(guardLo:guardHi) = false;

    if any(noiseIx)
        % Use noise audio for off-ridge noise estimate
        noiseSlice(i)  = mean(noiseBand(noiseIx, i));
        noiseSliceN(i) = noiseSlice(i);   % store for variance calc
    end
end

% Aggregate across slices
rmsSignal  = mean(sigSlice,   'omitnan');
rmsNoise   = mean(noiseSlice, 'omitnan');
noiseVar   = var(noiseSliceN(~isnan(noiseSliceN)));

% Per-slice SNR for diagnostics
sliceSnrdB = 10 * log10(sigSlice ./ noiseSlice);

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

% -------------------------------------------------------------------------

function specPsd = applyCalibration(specPsd, sF, sT, metadata)

adVpeakdB       = 10 * log10(1 / metadata.adPeakVolt.^2);
frontEndGain_dB = interp1(log10(metadata.frontEndFreq_Hz), ...
    metadata.frontEndGain_dB, log10(sF), 'linear', 'extrap');
caldB           = metadata.hydroSensitivity_dB + frontEndGain_dB + adVpeakdB;
caldB(isnan(caldB) | isinf(caldB)) = -1000;
calibration     = 10.^(caldB / 10);
specPsd         = specPsd ./ repmat(calibration(:), 1, size(specPsd, 2));

end
