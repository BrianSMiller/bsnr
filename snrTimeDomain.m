function [rmsSignal, rmsNoise, noiseVar, sigFilt, noiseFilt] = snrTimeDomain( ...
    sigAudio, noiseAudio, freq, sampleRate, metadata)
% Estimate signal and noise power by bandpass filtering in the time domain.
%
% Both signal and noise are filtered with a bandpass FIR. RMS power is
% computed from the squared filtered waveforms; noiseVar is the variance
% of the squared filtered noise waveform. The caller (annotationSNR)
% applies whichever SNR formula is requested.
%
% If metadata is provided, rmsSignal/rmsNoise/noiseVar are scaled to
% calibrated pressure units (µPa²). The calibration assumes a flat
% frequency response across the annotation band — the frontend gain is
% evaluated at the band centre frequency. This is consistent with the
% waveform calibration approach in calibratedPsdExample.m.
%
% Calibration formula (scalar, time-domain):
%   calFactor = adPeakVolt / 10^((hydroSensitivity_dB + gainAtCentre_dB) / 20)
%   rmsSignal_uPa2 = mean((sigFilt * calFactor).^2) = rmsSignal_wav * calFactor^2
%
% Filter design note: the filter is rebuilt on every call. Persistent
% variable caching is intentionally avoided because it is unreliable
% inside parfor workers. The design cost is negligible relative to
% audio I/O.
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples (column vector)
%   freq        [lowHz highHz] bandpass cutoff frequencies in Hz.
%               Both values must be strictly within (0, sampleRate/2).
%   sampleRate  Sample rate in Hz
%   metadata    (optional) Calibration metadata struct with fields:
%                 .hydroSensitivity_dB   dB re V/µPa
%                 .adPeakVolt            ADC peak voltage (V)
%                 .frontEndFreq_Hz       frequency axis for gain curve
%                 .frontEndGain_dB       gain at each frequency (dB)
%               If empty or omitted, output is in WAV (dBFS) units.
%
% OUTPUTS
%   rmsSignal  Mean instantaneous power of filtered signal (WAV or µPa²)
%   rmsNoise   Mean instantaneous power of filtered noise  (WAV or µPa²)
%   noiseVar   Variance of instantaneous noise power
%   sigFilt    Filtered signal waveform (WAV units, for diagnostic plotting)
%   noiseFilt  Filtered noise waveform  (WAV units, for diagnostic plotting)

if nargin < 5
    metadata = [];
end

% Filter order: must be large enough that transition bandwidth << passband.
% Rule: FilterOrder = max(48, round(10 * sampleRate / bandwidth)) gives
% transition bandwidth ≈ 3.3/N*fs ≈ 0.33 * bandwidth — adequate for most bands.
% This matters most for narrow bands at high sample rates (e.g. 40 Hz at 12 kHz).
filterOrder = max(48, round(10 * sampleRate / diff(freq)));
filterOrder = filterOrder + mod(filterOrder, 2);   % ensure even order
try
    d = designfilt('bandpassfir', 'FilterOrder', filterOrder, ...
        'CutoffFrequency1', freq(1), ...
        'CutoffFrequency2', freq(2), ...
        'SampleRate',       sampleRate);

    sigFilt   = filtfilt(d, sigAudio);
    noiseFilt = filtfilt(d, noiseAudio);

catch me
    warning('snrTimeDomain:failed', ...
        'Filter/filtfilt failed for freq=[%.1f %.1f] Hz, fs=%.1f Hz: %s', ...
        freq(1), freq(2), sampleRate, me.message);
    [rmsSignal, rmsNoise, noiseVar, sigFilt, noiseFilt] = ...
        deal(nan, nan, nan, [], []);
    return
end

% Apply scalar calibration if metadata is provided.
% Evaluate frontend gain at band centre frequency for a flat-in-band
% approximation — appropriate when the band is narrow relative to the
% gain curve variation (consistent with waveform calibration approach).
calFactor2 = 1;   % default: no calibration (power stays in WAV units)
if ~isempty(metadata)
    centreFreq = mean(freq);
    gainAtCentre = interp1(log10(metadata.frontEndFreq_Hz), ...
        metadata.frontEndGain_dB, log10(centreFreq), 'linear', 'extrap');
    % calFactor converts WAV amplitude to µPa:
    % pressure = wavData * adPeakVolt / 10^((sensitivity + gain) / 20)
    calFactor  = metadata.adPeakVolt / 10^((metadata.hydroSensitivity_dB + gainAtCentre) / 20);
    calFactor2 = calFactor^2;   % power scales as amplitude^2
end

rmsSignal = mean(sigFilt.^2)   * calFactor2;
rmsNoise  = mean(noiseFilt.^2) * calFactor2;
noiseVar  = var(noiseFilt.^2)  * calFactor2^2;   % variance scales as amplitude^4

end
