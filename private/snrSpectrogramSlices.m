function [rmsSignal, rmsNoise, noiseVar, methodData] = snrSpectrogramSlices( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate signal and noise power from per-slice spectrogram band power.
%
% For each time-slice, in-band power is computed using bandpower() on the
% PSD. Signal and noise power are the mean across their respective slice
% series; noiseVar is the variance across noise slices.
%
% INPUTS / OUTPUTS  see snrSpectrogram — identical interface.
%
% methodData fields:
%   .method           'spectrogramSlices'
%   .sigSlicePowers   per-slice signal band power
%   .noiseSlicePowers per-slice noise band power

[rmsSignal, ~, sigSlicePowers]        = slicePowerAndVariance( ...
    sigAudio,   nfft, nOverlap, nfft, sampleRate, freq, metadata);
[rmsNoise,  noiseVar, noiseSlicePowers] = slicePowerAndVariance( ...
    noiseAudio, nfft, nOverlap, nfft, sampleRate, freq, metadata);

methodData.method           = 'spectrogramSlices';
methodData.sigSlicePowers   = sigSlicePowers;
methodData.noiseSlicePowers = noiseSlicePowers;

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [power, variance, slicePowers] = slicePowerAndVariance( ...
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
slicePowers = slicePower;
power       = mean(slicePower);
variance    = var(slicePower);

end
