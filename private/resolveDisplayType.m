function displayType = resolveDisplayType(params, snrType, methodData)
% Resolve which display to use for a given method and params.
%
% Returns one of: 'spectrogram', 'timeSeries', 'histogram'
%
% Priority:
%   1. params.displayType if explicitly set
%   2. Per-method default
%
% INPUTS
%   params      Params struct (uses .displayType)
%   snrType     String, e.g. 'spectrogram', 'nist', 'timeDomain'
%   methodData  Standardised struct from SNR method with fields:
%                 .method           method name string
%                 .sigSlicePowers   per-slice signal powers ([] if n/a)
%                 .noiseSlicePowers per-slice noise powers  ([] if n/a)
%                 .sigFilt          filtered waveform (timeDomain only)
%                 .binCentres       NIST histogram bins (nist only)
%                 .psdCells         PSD cells (quantiles only)

hasSlices    = isfield(methodData, 'sigSlicePowers')   && ~isempty(methodData.sigSlicePowers);
hasSamples   = isfield(methodData, 'sigFilt')          && ~isempty(methodData.sigFilt);
hasNistHist  = isfield(methodData, 'binCentres')       && ~isempty(methodData.binCentres);
hasQuantHist = isfield(methodData, 'psdCells')         && ~isempty(methodData.psdCells);

% Caller-requested display type
requested = '';
if isfield(params, 'displayType') && ~isempty(params.displayType)
    requested = lower(params.displayType);
end

% Per-method defaults
if isempty(requested)
    switch lower(snrType)
        case 'nist'
            requested = 'histogram';
        case 'timedomain'
            requested = 'timeseries';
        otherwise
            requested = 'spectrogram';
    end
end

% Map to available display
switch requested
    case 'spectrogram'
        displayType = 'spectrogram';

    case {'timeseries', 'timedomain'}
        if hasSamples
            displayType = 'timeSeries';
        elseif hasSlices
            displayType = 'timeSeries';
        else
            displayType = 'spectrogram';
        end

    case 'histogram'
        displayType = 'histogram';

    otherwise
        displayType = 'spectrogram';
end

end
