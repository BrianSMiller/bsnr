function plotLurtonHistogram(spectrogramData, snr, rmsSignal, rmsNoise, noiseVar, levelUnit)
% Thin wrapper around plotBandHistogram for the spectrogram+Lurton case.
% Extracts per-slice powers from spectrogramData and delegates to
% plotBandHistogram with useLurton=true.
if nargin < 6 || isempty(levelUnit), levelUnit = 'dBFS'; end
plotBandHistogram(spectrogramData.signalSlicePowers, ...
    spectrogramData.noiseSlicePowers, snr, rmsSignal, rmsNoise, noiseVar, ...
    levelUnit, true);
end
