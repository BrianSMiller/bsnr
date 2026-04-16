function displayType = resolveDisplayType(params, snrType, methodData)
% Resolve which display to use for a given method and params.
%
% Returns one of: 'spectrogram', 'timeSeries', 'histogram', 'none'
%
% Priority:
%   1. params.displayType if explicitly set and available for this method
%   2. Per-method default
%
% Availability constraints:
%   'spectrogram' requires methodData.spectrogramData (full TF matrix)
%   'timeSeries'  requires methodData.sigSlicePowers or methodData.sigFilt
%   'histogram'   requires methodData.sigSlicePowers (or special histogram
%                 data for nist/quantiles)
%
% INPUTS
%   params      Params struct (uses .displayType)
%   snrType     String, e.g. 'spectrogram', 'nist', 'timeDomain'
%   methodData  Struct with fields set by the SNR computation:
%                 .spectrogramData  — from snrSpectrogram (has TF matrix)
%                 .sigSlicePowers   — per-slice signal powers
%                 .noiseSlicePowers — per-slice noise powers
%                 .sigFilt          — filtered waveform (timeDomain only)
%                 .histogramData    — NIST histogram struct
%                 .psdCells         — quantiles PSD cell array

% Determine what data is available
hasSpectro   = ~isempty(methodData.spectrogramData) && ...
               isstruct(methodData.spectrogramData) && ...
               isfield(methodData.spectrogramData, 'noiseSlicePowers');
hasSlices    = ~isempty(methodData.sigSlicePowers);
hasSamples   = ~isempty(methodData.sigFilt);
hasNistHist  = ~isempty(methodData.histogramData) && ...
               isstruct(methodData.histogramData) && ...
               isfield(methodData.histogramData, 'binCentres');
hasQuantHist = ~isempty(methodData.psdCells);

% Caller-requested display type
requested = '';
if isfield(params, 'displayType') && ~isempty(params.displayType)
    requested = lower(params.displayType);
end

% Per-method defaults when no explicit request
if isempty(requested)
    switch lower(snrType)
        case 'nist'
            requested = 'histogram';
        case 'quantiles'
            requested = 'spectrogram';
        case 'timedomain'
            requested = 'timeseries';
        otherwise
            requested = 'spectrogram';
    end
end

% Map requested to available display
switch requested
    case 'spectrogram'
        % Spectrogram needs the full TF matrix — only snrSpectrogram provides it.
        % All other methods fall back to timeSeries which is equally informative.
        if hasSpectro || strcmpi(snrType, 'spectrogram') || ...
                strcmpi(snrType, 'ridge') || strcmpi(snrType, 'synchrosqueeze') || ...
                strcmpi(snrType, 'spectrogramslices') || strcmpi(snrType, 'quantiles') || ...
                strcmpi(snrType, 'nist')
            displayType = 'spectrogram';
        else
            displayType = 'timeSeries';
        end

    case {'timeseries', 'timedomain'}
        if hasSamples
            displayType = 'timeSeries';   % per-sample FIR (timeDomain method)
        elseif hasSlices
            displayType = 'timeSeries';   % per-slice (all other methods)
        else
            displayType = 'spectrogram';  % fallback
        end

    case 'histogram'
        % All histogram types honoured
        displayType = 'histogram';

    otherwise
        displayType = 'spectrogram';
end

end
