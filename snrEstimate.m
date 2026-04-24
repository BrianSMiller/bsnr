function [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = snrEstimate(annot, varargin)
% Measure the signal-to-noise ratio (SNR) of one or more acoustic detections.
%
% Accepts either a params struct (legacy) or name-value pairs:
%
%   snr = snrEstimate(annot, params)
%   snr = snrEstimate(annot, 'snrType', 'spectrogramSlices', 'freq', [25 29])
%
% For full parameter documentation:
%   help snrEstimateImpl
%
% INPUTS
%   annot   - Scalar struct, struct array, or table of detections.
%             Required fields: soundFolder, t0, tEnd, duration, freq, channel.
%             t0/tEnd may be MATLAB datenums (double) or datetime objects.
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

[snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = snrEstimateImpl(annot, varargin{:});
end
