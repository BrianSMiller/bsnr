function metadata = simpleFlatMetadata()
% Return a simplified instrument metadata struct for gallery examples.
%
% Models a hydrophone recorder with:
%   - Flat frequency response in the passband (20 dB gain)
%   - Realistic AC coupling rolloff below ~5 Hz
%   - Realistic anti-aliasing filter rolloff above ~5 kHz
%   - Hydrophone sensitivity of -165 dB re V/uPa
%   - ADC peak voltage of 1.5 V (3 V peak-to-peak)
%   - Sample rate of 12000 Hz
%
% This simplified response is used in gallery examples for clarity.
% For real data, replace with the actual instrument metadata
% (e.g. metaDataKerguelen2024).

metadata.hydroSensitivity_dB = -165;
metadata.adPeakVolt          = 1.5;
metadata.sampleRate          = 12000;

% Frequency response: flat 20 dB with AC coupling ~5 Hz and AA filter ~5 kHz
%   1 Hz:    0 dB   (below AC coupling corner)
%   5 Hz:   14 dB   (AC coupling -6 dB point)
%   20 Hz:  20 dB   (fully in passband)
%   100 Hz: 20 dB   (flat passband)
%   5000 Hz: 3 dB   (AA filter -3 dB point)
%   10000 Hz: -60 dB (AA filter stopband)
metadata.frontEndFreq_Hz = [1    5   20   100   5000  10000];
metadata.frontEndGain_dB = [0   14   20    20      3    -60];

end
