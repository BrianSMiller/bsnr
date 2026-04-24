function annots = readTethysDetections(detections, soundFolder, options)
% Convert a Tethys Detections struct or XML file to a bsnr annotation array.
%
% Tethys stores detection metadata separately from audio file locations.
% The soundFolder argument maps deployments to local audio paths.
%
% USAGE
%   annots = readTethysDetections(detections, soundFolder)
%   annots = readTethysDetections(detections, soundFolder, 'channel', 2)
%   annots = readTethysDetections('detections.xml', soundFolder)
%
% INPUTS
%   detections   Tethys Detections as one of:
%                  - Struct array with fields Start, End, Parameters
%                    (as returned by a Tethys MATLAB client query)
%                  - Path to a Tethys Detections XML file (string/char)
%   soundFolder  Path to the folder of WAV files for this deployment.
%                If a containers.Map is provided, keys are DeploymentId
%                strings and values are folder paths (for multi-deployment
%                inputs).
%   options      Optional name-value pairs:
%                  channel      Recording channel index (default: 1)
%                  freqFallback [lowHz highHz] to use when MinFreq_Hz /
%                               MaxFreq_Hz are absent (default: [])
%
% OUTPUT
%   annots  Struct array with bsnr annotation fields:
%             .soundFolder     path to WAV files
%             .t0              detection start as MATLAB datenum
%             .tEnd            detection end as MATLAB datenum
%             .duration        duration in seconds
%             .freq            [MinFreq_Hz MaxFreq_Hz]
%             .channel         recording channel
%             .classification  species/call type string (if present)
%
% FIELD MAPPING
%   Tethys Detection.Start          -> annot.t0
%   Tethys Detection.End            -> annot.tEnd
%   Tethys Parameters.MinFreq_Hz    -> annot.freq(1)
%   Tethys Parameters.MaxFreq_Hz    -> annot.freq(2)
%   Tethys Parameters.Duration_s    -> annot.duration (fallback: End-Start)
%   Tethys OnEffort.Kind.Call       -> annot.classification
%
% NOTE
%   soundFolder does not exist in the Tethys Detection schema — it is a
%   bsnr-specific field that maps deployment metadata to local audio paths.
%   You must supply it separately.
%
% See also writeTethysXml, snrEstimate

arguments
    detections
    soundFolder
    options.channel      double   = 1
    options.freqFallback double   = []
end

%% Parse input format

if ischar(detections) || isstring(detections)
    % XML file path — parse with MATLAB xmlread
    detections = parseTethysXml(detections);
end

if isempty(detections)
    annots = struct([]);
    return
end

nDet = numel(detections);
annots = repmat(struct( ...
    'soundFolder',    '', ...
    't0',             nan, ...
    'tEnd',           nan, ...
    'duration',       nan, ...
    'freq',           [], ...
    'channel',        options.channel, ...
    'classification', ''), nDet, 1);

for i = 1:nDet
    d = detections(i);

    %% soundFolder
    if isa(soundFolder, 'containers.Map')
        % Multi-deployment: look up by DeploymentId
        if isfield(d, 'DeploymentId') && soundFolder.isKey(d.DeploymentId)
            annots(i).soundFolder = soundFolder(d.DeploymentId);
        else
            warning('readTethysDetections:missingDeployment', ...
                'No soundFolder mapping for detection %d (DeploymentId=%s).', ...
                i, getfield_safe(d, 'DeploymentId', '?'));
            annots(i).soundFolder = '';
        end
    else
        annots(i).soundFolder = char(soundFolder);
    end

    %% Times — Tethys uses ISO 8601 dateTime strings
    annots(i).t0   = tethysDateToDatenum(getfield_safe(d, 'Start', ''));
    annots(i).tEnd = tethysDateToDatenum(getfield_safe(d, 'End',   ''));

    if isnan(annots(i).t0)
        warning('readTethysDetections:missingStart', ...
            'Detection %d has no Start time — skipping.', i);
        continue
    end

    %% Duration
    p = getfield_safe(d, 'Parameters', struct());
    durSec = getfield_safe(p, 'Duration_s', nan);
    if ~isnan(durSec) && durSec > 0
        annots(i).duration = durSec;
        if isnan(annots(i).tEnd)
            annots(i).tEnd = annots(i).t0 + durSec / 86400;
        end
    elseif ~isnan(annots(i).tEnd)
        annots(i).duration = (annots(i).tEnd - annots(i).t0) * 86400;
    end

    %% Frequency band
    minFreq = getfield_safe(p, 'MinFreq_Hz', nan);
    maxFreq = getfield_safe(p, 'MaxFreq_Hz', nan);
    if ~isnan(minFreq) && ~isnan(maxFreq)
        annots(i).freq = [minFreq, maxFreq];
    elseif ~isempty(options.freqFallback)
        annots(i).freq = options.freqFallback;
    else
        warning('readTethysDetections:missingFreq', ...
            ['Detection %d has no MinFreq_Hz/MaxFreq_Hz and no freqFallback. ' ...
             'Set options.freqFallback or the snrEstimate freq parameter.'], i);
    end

    %% Classification
    annots(i).classification = getfield_safe(d, 'Call', '');
end

% Remove any detections with no valid start time
valid = ~isnan([annots.t0]);
if any(~valid)
    warning('readTethysDetections:skippedDetections', ...
        '%d detection(s) skipped due to missing Start time.', sum(~valid));
    annots = annots(valid);
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function dn = tethysDateToDatenum(isoStr)
% Convert ISO 8601 dateTime string to MATLAB datenum.
% Tethys format: '2019-03-14T22:15:30.000Z' or '2019-03-14T22:15:30'
if isempty(isoStr)
    dn = nan;
    return
end
isoStr = regexprep(char(isoStr), 'T', ' ');
isoStr = regexprep(isoStr, 'Z$', '');
isoStr = regexprep(isoStr, '\.\d+$', '');  % strip sub-second precision
try
    dn = datenum(isoStr, 'yyyy-mm-dd HH:MM:SS');
catch
    dn = nan;
end
end

function annots = parseTethysXml(xmlFile)
% Parse a Tethys Detections XML file into a struct array.
% Extracts Detection elements and maps to a flat struct with fields:
%   Start, End, Parameters.MinFreq_Hz, Parameters.MaxFreq_Hz,
%   Parameters.Duration_s, Call.

try
    doc  = xmlread(xmlFile);
catch err
    error('readTethysDetections:xmlReadFailed', ...
        'Could not parse XML file: %s\n%s', xmlFile, err.message);
end

detNodes = doc.getElementsByTagName('Detection');
n = detNodes.getLength();
if n == 0
    annots = struct([]);
    return
end

annots = repmat(struct('Start','','End','','Call','','Parameters',struct()), n, 1);

for i = 1:n
    node = detNodes.item(i-1);
    annots(i).Start = getXmlText(node, 'Start');
    annots(i).End   = getXmlText(node, 'End');

    % Parameters sub-element
    pNodes = node.getElementsByTagName('Parameters');
    if pNodes.getLength() > 0
        pNode = pNodes.item(0);
        annots(i).Parameters.MinFreq_Hz  = str2double(getXmlText(pNode, 'MinFreq_Hz'));
        annots(i).Parameters.MaxFreq_Hz  = str2double(getXmlText(pNode, 'MaxFreq_Hz'));
        annots(i).Parameters.Duration_s  = str2double(getXmlText(pNode, 'Duration_s'));
        annots(i).Parameters.SNR_dB      = str2double(getXmlText(pNode, 'SNR_dB'));
        annots(i).Parameters.ReceivedLevel_dB = str2double(getXmlText(pNode, 'ReceivedLevel_dB'));
    end

    % Call type — may be at Detection level or in a Kind element
    annots(i).Call = getXmlText(node, 'Call');
end

end

function txt = getXmlText(node, tagName)
% Get text content of first child element with given tag name.
nodes = node.getElementsByTagName(tagName);
if nodes.getLength() > 0
    txt = char(nodes.item(0).getTextContent());
else
    txt = '';
end
end

function val = getfield_safe(s, field, default)
% Return s.field if it exists and is non-empty, otherwise default.
if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
    val = s.(field);
else
    val = default;
end
end
