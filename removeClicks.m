function newData = removeClicks(sourceData, threshold,  power) 
% newData = removeClicks(sourceData, threshold,  power) {
% Click removal PAMGuard style - e.g. for a short chunk of audio (e.g.
% spectrogram slice).
% SourceData - vector with time domain data
% threshold - Threshold for a click to be removed (number of standard
%   deviations above background)
% power - The magnitude of the removal effect -- make larger to further
%   reduce amplitude of clicks?
thresh = threshold * std(sourceData);
if (thresh <= 0.)
    newData = sourceData;
else
    weights = 1./(1 +  ((sourceData-mean(sourceData))./thresh).^power);
    newData = weights.*sourceData;
end