function [rmsSignal, rmsNoise, noiseVar, ridgeFreq, sliceSnrdB] = snrSynchrosqueeze( ...
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
%                 .guardBins     Bins either side of ridge excluded from
%                                noise estimate (default 2)
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
    [rmsSignal, rmsNoise, noiseVar, ridgeFreq, sliceSnrdB] = ...
        deal(nan, nan, nan, nan(1), nan(1));
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
    [rmsSignal, rmsNoise, noiseVar, ridgeFreq, sliceSnrdB] = ...
        deal(nan, nan, nan, nan(size(sT)), nan(size(sT)));
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
%% Per-slice signal and noise power
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% For the signal: measure power at the ridge bin per time slice.
% For the noise: use a single per-bin mean across all noise slices.
% This is more robust than per-slice noise matching when noise audio
% has been spliced (exclusion zone removed) and may have a different
% number of slices than the signal audio.
nSlices  = length(sT);
sigSlice = nan(nSlices, 1);

% Pre-compute per-bin mean and variance of noise across all its slices
noiseBinMean = mean(noiseBand, 2);   % nBins x 1
noiseBinVar  = var(noiseBand,  0, 2); % nBins x 1

noiseSlice = nan(nSlices, 1);
noiseVarSlice = nan(nSlices, 1);

for i = 1:nSlices
    rb = ridgeBinIdx(i);
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
sliceSnrdB = 10 * log10(sigSlice ./ noiseSlice);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helper
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function specPsd = applyCalibration(specPsd, sF, sT, metadata)

adVpeakdB       = 10 * log10(1 / metadata.adPeakVolt.^2);
frontEndGain_dB = interp1(log10(metadata.frontEndFreq_Hz), ...
    metadata.frontEndGain_dB, log10(sF), 'linear', 'extrap');
caldB           = metadata.hydroSensitivity_dB + frontEndGain_dB + adVpeakdB;
caldB(isnan(caldB) | isinf(caldB)) = -1000;
calibration     = 10.^(caldB / 10);
specPsd         = specPsd ./ repmat(calibration(:), 1, size(specPsd, 2));

end
