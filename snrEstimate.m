function [snr, rmsSignal, rmsNoise, noiseVar, fileInfo, resolvedParams] = snrEstimate(annot, varargin)
% Measure the signal-to-noise ratio (SNR) of one or more acoustic detections.
%
% Accepts either a params struct (legacy) or name-value pairs:
%
%   result = snrEstimate(annot)
%   result = snrEstimate(annot, 'snrType', 'spectrogramSlices', 'freq', [25 29])
%   result = snrEstimate(annot, params)   % legacy struct syntax
%
% Always returns a result table — even for a single annotation.
%
% OUTPUTS
%   snr            Result table with columns:
%                    snr, signalRMSdB, noiseRMSdB, noiseVar
%                  When calibration is provided, also:
%                    signalBandLevel_dBuPa, noiseBandLevel_dBuPa
%   rmsSignal      [] (use snr.signalRMSdB)
%   rmsNoise       [] (use snr.noiseRMSdB)
%   noiseVar       [] (use snr.noiseVar)
%   fileInfo       [] 
%   resolvedParams Parameter struct with all defaults and derived values
%                  filled in (including computed nfft). Record alongside
%                  results for reproducibility.
%
% For full parameter documentation:
%   help snrEstimateImpl
%
% See also snrEstimateImpl, trimAnnotation, bsnr

% Convert legacy struct input to name-value pairs
if numel(varargin) == 1 && isstruct(varargin{1})
    s        = varargin{1};
    fields   = fieldnames(s);
    vals     = struct2cell(s);
    nv       = [fields, vals]';
    varargin = nv(:)';
end

[snr, rmsSignal, rmsNoise, noiseVar, fileInfo, resolvedParams] = ...
    snrEstimateImpl(annot, varargin{:});
end
