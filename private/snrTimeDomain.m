function [rmsSignal, rmsNoise, noiseVar, methodData] = snrTimeDomain( ...
    sigAudio, noiseAudio, freq, sampleRate, metadata)
% Estimate signal and noise power by bandpass filtering in the time domain.
%
% Both signal and noise are filtered with a bandpass FIR. RMS power is
% computed from the squared filtered waveforms.
%
% Note: this method operates entirely in the time domain and does not use
% nfft or nOverlap. The interface is intentionally different from
% spectrogram-based methods.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples (column vector)
%   freq        [lowHz highHz] bandpass cutoff frequencies in Hz
%   sampleRate  Sample rate in Hz
%   metadata    (optional) Calibration metadata struct
%
% OUTPUTS
%   rmsSignal   Mean instantaneous power of filtered signal
%   rmsNoise    Mean instantaneous power of filtered noise
%   noiseVar    Variance of instantaneous noise power
%   methodData  Struct with fields:
%                 .method     'timeDomain'
%                 .sigFilt    Filtered signal waveform (WAV units)
%                 .noiseFilt  Filtered noise waveform (WAV units)
%                 .sigSlicePowers   [] (not applicable for time domain)
%                 .noiseSlicePowers [] (not applicable for time domain)

if nargin < 5, metadata = []; end

filterOrder = max(48, round(10 * sampleRate / diff(freq)));
filterOrder = filterOrder + mod(filterOrder, 2);

nyquist = sampleRate / 2;
if freq(1) <= 0 || freq(2) >= nyquist * 1.01
    [rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan);
    methodData = emptyMethodData('timeDomain');
    return
end
freqSafe = [max(freq(1), nyquist * 0.01), min(freq(2), nyquist * 0.99)];

try
    d = designfilt('bandpassfir', 'FilterOrder', filterOrder, ...
        'CutoffFrequency1', freqSafe(1), ...
        'CutoffFrequency2', freqSafe(2), ...
        'SampleRate',       sampleRate);
    sigFilt   = filtfilt(d, sigAudio);
    noiseFilt = filtfilt(d, noiseAudio);
catch
    [rmsSignal, rmsNoise, noiseVar] = deal(nan, nan, nan);
    methodData = emptyMethodData('timeDomain');
    return
end

calFactor2 = 1;
if ~isempty(metadata)
    centreFreq   = mean(freq);
    gainAtCentre = interp1(log10(metadata.frontEndFreq_Hz), ...
        metadata.frontEndGain_dB, log10(centreFreq), 'linear', 'extrap');
    calFactor  = metadata.adPeakVolt / 10^((metadata.hydroSensitivity_dB + gainAtCentre) / 20);
    calFactor2 = calFactor^2;
end

rmsSignal = mean(sigFilt.^2)   * calFactor2;
rmsNoise  = mean(noiseFilt.^2) * calFactor2;
noiseVar  = var(noiseFilt.^2)  * calFactor2^2;

methodData.method           = 'timeDomain';
methodData.sigFilt          = sigFilt;
methodData.noiseFilt        = noiseFilt;
methodData.sigSlicePowers   = [];
methodData.noiseSlicePowers = [];

end

function md = emptyMethodData(method)
md.method           = method;
md.sigFilt          = [];
md.noiseFilt        = [];
md.sigSlicePowers   = [];
md.noiseSlicePowers = [];
end
