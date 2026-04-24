function [rmsSignal, rmsNoise, noiseVar, methodData] = snrSpectrogram( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate signal and noise power from spectrogram cells within a frequency band.
%
% Computes the mean PSD across all time-frequency cells within freq for
% both signal and noise audio. The caller (snrEstimate) applies whichever
% SNR formula is requested.
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
%   rmsSignal   Mean signal PSD in band (linear)
%   rmsNoise    Mean noise PSD in band (linear)
%   noiseVar    Variance of noise PSD across all cells in band
%   methodData  Struct with fields:
%                 .method           'spectrogram'
%                 .sigSlicePowers   per-slice total band power, signal window
%                 .noiseSlicePowers per-slice total band power, noise window
%                 .df               Hz per FFT bin

[rmsSignal, ~, sigSlicePowers, df] = ...
    spectrogramPowerAndVariance(sigAudio,   nfft, nOverlap, nfft, sampleRate, freq, metadata);
[rmsNoise, noiseVar, noiseSlicePowers, ~] = ...
    spectrogramPowerAndVariance(noiseAudio, nfft, nOverlap, nfft, sampleRate, freq, metadata);

methodData.method           = 'spectrogram';
methodData.sigSlicePowers   = sigSlicePowers;
methodData.noiseSlicePowers = noiseSlicePowers;
methodData.df               = df;

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [power, variance, slicePowers, df] = spectrogramPowerAndVariance( ...
    x, window, nOverlap, nfft, sampleRate, freqRange, metadata)

if length(x) < window
    window   = length(x);
    nOverlap = 0;
    nfft     = window;
end
x = x - mean(x);

try
    [~, sF, sT, specPsd] = spectrogram(x, window, nOverlap, nfft, sampleRate);
catch
    [power, variance, slicePowers, df] = deal(nan, nan, nan, nan);
    return
end

if ~isempty(metadata)
    specPsd = applyCalibration(specPsd, sF, sT, metadata);
end

fIx         = sF >= freqRange(1) & sF <= freqRange(2);
specPsd     = specPsd(fIx, :);
df          = sF(2) - sF(1);
slicePowers = sum(specPsd, 1) * df;
power       = mean(slicePowers);
variance    = var(slicePowers);

end
