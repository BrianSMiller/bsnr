function xmlStr = writeTethysXml(result, annots, options)
% Write bsnr results as a Tethys-compatible Detections XML document.
%
% Produces valid XML conforming to the Tethys 3.x Detections schema,
% without requiring the Nilus Java library or a running Tethys server.
% The output can be ingested by a Tethys server or submitted to the
% NOAA NCEI Passive Acoustic Data Archive (which uses the Tethys schema
% and aligns with ASA Standards for Acoustic Metadata).
%
% NOTE ON MAKARA
%   NOAA is developing Makara as a successor to Tethys for US-centric
%   passive acoustic data management. Makara uses CSV templates rather
%   than XML and is currently under development (as of 2025). When the
%   Makara format stabilises, a writeMakaraDetections() companion function
%   will be added. For now, writeTethysXml covers the NCEI submission path.
%
% USAGE
%   xmlStr = writeTethysXml(result, annots)
%   xmlStr = writeTethysXml(result, annots, 'project', 'SORP', ...)
%   writeTethysXml(result, annots, 'outputFile', 'snr_results.xml')
%
% INPUTS
%   result   bsnr result table (from snrEstimate). Required columns:
%              snr           — SNR in dB
%            Optional columns (included when present):
%              signalBandLevel_dBuPa  — mapped to ReceivedLevel_dB
%              noiseRMSdB             — noise level
%   annots   Annotation struct array or table corresponding to result rows.
%            Required fields: t0, tEnd, freq.
%            Optional fields: classification, channel, soundFolder.
%
%   Optional name-value parameters:
%     project      Tethys DataSource project name (default: '')
%     site         Tethys DataSource site (default: '')
%     deploymentId Tethys DataSource deployment ID (default: '')
%     software     Algorithm software name (default: 'bsnr')
%     version      Algorithm version (default: '')
%     userId       Analyst user ID (default: '')
%     outputFile   If provided, write XML to this file path
%
% OUTPUT
%   xmlStr   XML string. Empty if result is empty.
%
% FIELD MAPPING
%   annot.t0                      -> Detection.Start (ISO 8601)
%   annot.tEnd                    -> Detection.End
%   annot.freq(1)                 -> Parameters.MinFreq_Hz
%   annot.freq(2)                 -> Parameters.MaxFreq_Hz
%   annot.duration                -> Parameters.Duration_s
%   annot.classification          -> Detection.Parameters.Subtype
%   result.snr                    -> Parameters.SNR_dB
%   result.signalBandLevel_dBuPa  -> Parameters.ReceivedLevel_dB
%
% See also readTethysDetections, snrEstimate

arguments
    result   table
    annots
    options.project      char   = ''
    options.site         char   = ''
    options.deploymentId char   = ''
    options.software     char   = 'bsnr'
    options.version      char   = ''
    options.userId       char   = ''
    options.outputFile   char   = ''
end

if istable(annots)
    annots = table2struct(annots);
end

nDet = height(result);
if nDet == 0
    xmlStr = '';
    return
end

if numel(annots) ~= nDet
    error('writeTethysXml:sizeMismatch', ...
        'result has %d rows but annots has %d elements.', nDet, numel(annots));
end

hasCal = ismember('signalBandLevel_dBuPa', result.Properties.VariableNames);

%% Build XML string
lines = {};

% Use a cell array and grow it
lines{1} = '<?xml version="1.0" encoding="UTF-8"?>';
lines{end+1} = '<Detections xmlns="http://tethys.sdsu.edu/schema/1.0">';

% DataSource
lines{end+1} = '  <DataSource>';
if ~isempty(options.project),      lines{end+1} = sprintf('    <Project>%s</Project>',           xmlEscape(options.project));      end
if ~isempty(options.site),         lines{end+1} = sprintf('    <Site>%s</Site>',                 xmlEscape(options.site));         end
if ~isempty(options.deploymentId), lines{end+1} = sprintf('    <DeploymentId>%s</DeploymentId>', xmlEscape(options.deploymentId)); end
lines{end+1} = '  </DataSource>';

% Algorithm
lines{end+1} = '  <Algorithm>';
lines{end+1} = sprintf('    <Software>%s</Software>', xmlEscape(options.software));
if ~isempty(options.version)
    lines{end+1} = sprintf('    <Version>%s</Version>', xmlEscape(options.version));
end
lines{end+1} = '    <Parameters/>';
lines{end+1} = '  </Algorithm>';

% UserID
if ~isempty(options.userId)
    lines{end+1} = sprintf('  <UserID>%s</UserID>', xmlEscape(options.userId));
end

% Effort — minimal required element
lines{end+1} = '  <Effort>';
if nDet > 0
    lines{end+1} = sprintf('    <Start>%s</Start>', datenumsToIso(annots(1).t0));
    lines{end+1} = sprintf('    <End>%s</End>',     datenumsToIso(annots(nDet).tEnd));
end
lines{end+1} = '  </Effort>';

% OnEffort block containing all detections
lines{end+1} = '  <OnEffort>';

for i = 1:nDet
    an  = annots(i);
    snr = result.snr(i);

    lines{end+1} = '    <Detection>';
    lines{end+1} = sprintf('      <Start>%s</Start>', datenumsToIso(an.t0));
    if ~isnan(an.tEnd)
        lines{end+1} = sprintf('      <End>%s</End>', datenumsToIso(an.tEnd));
    end

    lines{end+1} = '      <Parameters>';

    % Classification -> Subtype
    if isfield(an, 'classification') && ~isempty(an.classification)
        lines{end+1} = sprintf('        <Subtype>%s</Subtype>', xmlEscape(an.classification));
    end

    % SNR
    if ~isnan(snr)
        lines{end+1} = sprintf('        <SNR_dB>%.4f</SNR_dB>', snr);
    end

    % Calibrated received level
    if hasCal && ~isnan(result.signalBandLevel_dBuPa(i))
        lines{end+1} = sprintf('        <ReceivedLevel_dB>%.4f</ReceivedLevel_dB>', ...
            result.signalBandLevel_dBuPa(i));
    end

    % Frequency band
    if isfield(an, 'freq') && ~isempty(an.freq) && numel(an.freq) >= 2
        lines{end+1} = sprintf('        <MinFreq_Hz>%.2f</MinFreq_Hz>', an.freq(1));
        lines{end+1} = sprintf('        <MaxFreq_Hz>%.2f</MaxFreq_Hz>', an.freq(2));
    end

    % Duration
    if isfield(an, 'duration') && ~isempty(an.duration) && ~isnan(an.duration)
        lines{end+1} = sprintf('        <Duration_s>%.4f</Duration_s>', an.duration);
    end

    lines{end+1} = '      </Parameters>';
    lines{end+1} = '    </Detection>';
end

lines{end+1} = '  </OnEffort>';
lines{end+1} = '</Detections>';

xmlStr = strjoin(lines, newline);

%% Write to file if requested
if ~isempty(options.outputFile)
    fid = fopen(options.outputFile, 'w', 'n', 'UTF-8');
    if fid < 0
        error('writeTethysXml:cannotOpenFile', ...
            'Cannot open output file for writing: %s', options.outputFile);
    end
    fprintf(fid, '%s\n', xmlStr);
    fclose(fid);
    if nargout == 0
        fprintf('Wrote %d detections to %s\n', nDet, options.outputFile);
    end
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function iso = datenumsToIso(dn)
% Convert MATLAB datenum to ISO 8601 dateTime string for Tethys.
% Output format: 2019-03-14T22:15:30
if isnan(dn)
    iso = '';
    return
end
dv  = datevec(dn);
iso = sprintf('%04d-%02d-%02dT%02d:%02d:%02d', ...
    dv(1), dv(2), dv(3), dv(4), dv(5), round(dv(6)));
end

function s = xmlEscape(s)
% Escape special XML characters in a string.
s = strrep(s, '&',  '&amp;');
s = strrep(s, '<',  '&lt;');
s = strrep(s, '>',  '&gt;');
s = strrep(s, '"',  '&quot;');
s = strrep(s, '''', '&apos;');
end
