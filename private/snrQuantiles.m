function [rmsSignal, rmsNoise, noiseVar, methodData] = snrQuantiles( ...
    sigAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate signal and noise power using quantiles of the spectrogram distribution.
%
% Signal power is the mean of cells at or above the 85th percentile of the
% signal spectrogram; noise power is the mean of cells below that threshold.
% Both estimates are derived from the signal audio window alone — this method
% requires no separate noise window.
%
% Note: this method has a different input signature from other SNR methods
% (no noiseAudio argument) because it operates on the signal window only.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   nfft        FFT length (samples)
%   nOverlap    Window overlap (samples)
%   sampleRate  Sample rate in Hz
%   freq        [lowHz highHz] frequency band
%   metadata    Calibration metadata struct, or [] for no calibration
%
% OUTPUTS
%   rmsSignal   Mean PSD of high-percentile (top 15%) cells
%   rmsNoise    Mean PSD of low-percentile (bottom 85%) cells
%   noiseVar    Variance of low-percentile cells
%   methodData  Struct with fields:
%                 .method           'quantiles'
%                 .q85thresh        85th percentile PSD threshold
%                 .psdCells         all in-band PSD cell values
%                 .sigSlicePowers   [] (within-window; no slice series)
%                 .noiseSlicePowers [] (within-window; no noise window)

if nargin < 6, metadata = []; end

window = nfft;
if length(sigAudio) < window
    window   = length(sigAudio);
    nOverlap = 0;
    nfft     = window;
end

[~, F, T, P] = spectrogram(sigAudio, window, nOverlap, nfft, sampleRate);

if ~isempty(metadata)
    P = applyCalibration(P, F, T, metadata);
end

specPsd  = P(F >= freq(1) & F <= freq(2), :);
q85      = quantile(specPsd(:), 0.85);
sigIx    = specPsd >= q85;
noiseIx  = specPsd <  q85;

rmsSignal = mean(specPsd(sigIx));
rmsNoise  = mean(specPsd(noiseIx));
noiseVar  = var( specPsd(noiseIx));

methodData.method           = 'quantiles';
methodData.q85thresh        = q85;
methodData.psdCells         = specPsd(:);
methodData.sigSlicePowers   = [];
methodData.noiseSlicePowers = [];

end
