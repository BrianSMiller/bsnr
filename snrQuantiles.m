function [rmsSignal, rmsNoise, noiseVar, q85thresh, psdCells] = snrQuantiles( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate signal and noise power using quantiles of the spectrogram distribution.
%
% Signal power is the mean of cells at or above the 85th percentile of the
% signal spectrogram; noise power is the mean of cells below that threshold.
% Both estimates are derived from the signal audio window alone (noiseAudio
% is accepted for interface consistency but not used).
%
% This is an experimental method — use spectrogram or timeDomain for
% production work.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples — not used, for interface consistency
%   nfft        FFT length (samples)
%   nOverlap    Window overlap (samples)
%   sampleRate  Sample rate in Hz
%   freq        [lowHz highHz] frequency band
%   metadata    Calibration metadata struct, or [] for no calibration
%
% OUTPUTS
%   rmsSignal  Mean PSD of high-percentile (top 15%) cells
%   rmsNoise   Mean PSD of low-percentile (bottom 85%) cells
%   noiseVar   Variance of low-percentile cells
%   q85thresh  85th percentile PSD threshold (linear, V^2/Hz or Pa^2/Hz)
%   psdCells   All in-band PSD cell values (column vector, for histogram display)

if nargin < 7, metadata = []; end

[rmsSignal, rmsNoise, noiseVar, q85thresh, psdCells] = quantilePower( ...
    sigAudio, nfft, nOverlap, sampleRate, freq, metadata);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [signal, noise, noiseVar, q85thresh, psdCells] = quantilePower(x, window, nOverlap, sampleRate, freq, metadata)

nfft = window;
if length(x) < window
    window   = length(x);
    nOverlap = 0;
    nfft     = window;
end

[~, F, sT, P] = spectrogram(x, window, nOverlap, nfft, sampleRate);

% Apply calibration if provided
if ~isempty(metadata)
    P = applyCalibration(P, F, sT, metadata);
end

specPsd   = P(F >= freq(1) & F <= freq(2), :);
q85       = quantile(specPsd(:), 0.85);
sigIx     = specPsd >= q85;
noiseIx   = specPsd <  q85;
signal    = mean(specPsd(sigIx));
noise     = mean(specPsd(noiseIx));
noiseVar  = var( specPsd(noiseIx));
q85thresh = q85;
psdCells  = specPsd(:);   % all in-band cells, for histogram display

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function specPsd = applyCalibration(specPsd, sF, sT, metadata)
adVpeakdB       = 10 * log10(1 / metadata.adPeakVolt.^2);
frontEndGain_dB = interp1(log10(metadata.frontEndFreq_Hz), ...
    metadata.frontEndGain_dB, log10(sF), 'linear', 'extrap');
caldB           = metadata.hydroSensitivity_dB + frontEndGain_dB + adVpeakdB;
caldB(isnan(caldB) | isinf(caldB)) = -1000;
specPsd         = specPsd ./ repmat(10.^(caldB/10), 1, size(specPsd, 2));
end
