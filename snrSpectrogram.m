function [rmsSignal, rmsNoise, noiseVar] = snrSpectrogram( ...
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
%   rmsSignal  Mean signal PSD in band (linear)
%   rmsNoise   Mean noise PSD in band (linear)
%   noiseVar   Variance of noise PSD across all cells in band

[rmsSignal, ~]        = spectrogramPowerAndVariance( ...
    sigAudio,   nfft, nOverlap, nfft, sampleRate, freq, metadata);
[rmsNoise,  noiseVar] = spectrogramPowerAndVariance( ...
    noiseAudio, nfft, nOverlap, nfft, sampleRate, freq, metadata);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [power, variance] = spectrogramPowerAndVariance( ...
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
    [power, variance] = deal(nan, nan);
    return
end

if ~isempty(metadata)
    specPsd = applyCalibration(specPsd, sF, sT, metadata);
end

fIx      = sF >= freqRange(1) & sF <= freqRange(2);
specPsd  = specPsd(fIx, :);
df       = sF(2) - sF(1);   % Hz per bin

% Integrate power spectrally: sum(PSD)*df gives total band power per time slice.
% This correctly recovers both tonal and broadband signal levels:
% - For broadband noise: sum(PSD)*df = mean(PSD)*bandwidth
% - For a tone: sum(PSD)*df captures all energy regardless of nBins
% power = mean band power in uPa^2 (or WAV^2 without calibration).
% SNR = signal_power / noise_power is still correct since bandwidth cancels.
% Absolute level: 10*log10(power) = dB re 1 uPa (with calibration).
power    = mean(sum(specPsd, 1) * df);   % mean total band power
variance = var(  sum(specPsd, 1) * df);  % variance of per-slice band power

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
