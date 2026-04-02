function [rmsSignal, rmsNoise, noiseVar] = snrSpectrogramSlices( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate signal and noise power from per-slice spectrogram band power.
%
% For each time-slice, in-band power is computed using bandpower() on the
% PSD. Signal and noise power are the mean across their respective slice
% series; noiseVar is the variance across noise slices. This follows the
% premise of Lurton (2010) of estimating power from a time series of
% band-limited measurements, and was the method used in:
%   Miller et al. (2021) Annotated Library
%   Miller et al. (2022) Deep Learning D-call paper
%
% The caller (snrEstimate) applies whichever SNR formula is requested.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples (column vector)
%   nfft        FFT length (samples)
%   nOverlap    Window overlap (samples)
%   sampleRate  Sample rate in Hz
%   freq        [lowHz highHz] frequency band for power integration
%   metadata    Calibration metadata struct, or [] for no calibration
%
% OUTPUTS
%   rmsSignal  Mean signal power across slices (linear)
%   rmsNoise   Mean noise power across slices (linear)
%   noiseVar   Variance of noise power across slices

[rmsSignal, ~]        = slicePowerAndVariance( ...
    sigAudio,   nfft, nOverlap, nfft, sampleRate, freq, metadata);
[rmsNoise,  noiseVar] = slicePowerAndVariance( ...
    noiseAudio, nfft, nOverlap, nfft, sampleRate, freq, metadata);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [power, variance] = slicePowerAndVariance( ...
    x, window, nOverlap, nfft, sampleRate, freqRange, metadata)

if length(x) < window
    window   = length(x);
    nOverlap = 0;
    nfft     = window;
end
x = x - mean(x);

[~, sF, sT, specPsd] = spectrogram(x, window, nOverlap, nfft, sampleRate);

if ~isempty(metadata)
    specPsd = applyCalibration(specPsd, sF, sT, metadata);
end

slicePower = nan(size(sT));
for i = 1:length(sT)
    slicePower(i) = bandpower(specPsd(:,i), sF, freqRange, 'psd');
end
power    = mean(slicePower);
variance = var(slicePower);

end

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
