function specPsd = applyCalibration(specPsd, sF, ~, metadata)
% Apply instrument calibration to a PSD matrix.
%
% Converts raw spectrogram PSD (V^2/Hz) to calibrated acoustic PSD (Pa^2/Hz)
% using hydrophone sensitivity, frontend gain, and ADC peak voltage.
%
% INPUTS
%   specPsd   PSD matrix [nFreqBins x nSlices], V^2/Hz
%   sF        Frequency axis vector (Hz), length nFreqBins
%   ~         Time axis (unused, accepted for interface consistency)
%   metadata  Calibration struct with fields:
%               .hydroSensitivity_dB   dB re V/µPa
%               .adPeakVolt            ADC peak voltage (V)
%               .frontEndFreq_Hz       frequency axis for gain curve
%               .frontEndGain_dB       gain at each frequency (dB)
%
% OUTPUT
%   specPsd   Calibrated PSD matrix (Pa^2/Hz)

adVpeakdB       = 10 * log10(1 / metadata.adPeakVolt.^2);
frontEndGain_dB = interp1(log10(metadata.frontEndFreq_Hz), ...
    metadata.frontEndGain_dB, log10(sF), 'linear', 'extrap');
caldB           = metadata.hydroSensitivity_dB + frontEndGain_dB + adVpeakdB;
caldB(isnan(caldB) | isinf(caldB)) = -1000;
calibration     = 10.^(caldB / 10);
specPsd         = specPsd ./ repmat(calibration(:), 1, size(specPsd, 2));

end
