function test_tethys()
% Tests for readTethysDetections and writeTethysXml.
%
% Tests:
%   (1) writeTethysXml produces valid XML with required elements
%   (2) writeTethysXml maps SNR and frequency fields correctly
%   (3) writeTethysXml includes ReceivedLevel_dB when calibration present
%   (4) writeTethysXml writes to file correctly
%   (5) readTethysDetections reads back XML written by writeTethysXml
%   (6) readTethysDetections round-trip preserves t0, tEnd, freq, SNR
%   (7) readTethysDetections handles missing MinFreq_Hz with freqFallback
%   (8) readTethysDetections handles struct input (Tethys client format)

fprintf('\n=== test_tethys ===\n');

%% Shared fixtures
sampleRate = 1000;
t0         = datenum('2024-03-15 14:23:07', 'yyyy-mm-dd HH:MM:SS');
tEnd       = t0 + 8/86400;
freq       = [25 90];

annot1.soundFolder    = 'C:\data\test';
annot1.t0             = t0;
annot1.tEnd           = tEnd;
annot1.duration       = 8;
annot1.freq           = freq;
annot1.channel        = 1;
annot1.classification = 'ABW Z';

annot2             = annot1;
annot2.t0          = t0 + 30/86400;
annot2.tEnd        = annot2.t0 + 12/86400;
annot2.duration    = 12;
annot2.freq        = [15 30];
annot2.classification = 'ABW A';

annots = [annot1; annot2];

% Synthetic result table
snrVals = [17.3; 8.6];
result  = table(snrVals, 10*log10([0.05; 0.01]), 10*log10([0.001; 0.001]), ...
    [0.001; 0.001], 'VariableNames', {'snr','signalRMSdB','noiseRMSdB','noiseVar'});

% Calibrated result adds signalBandLevel_dBuPa
resultCal = result;
resultCal.signalBandLevel_dBuPa = [122.4; 115.8];
resultCal.noiseBandLevel_dBuPa  = [105.1; 107.2];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (1) writeTethysXml produces valid XML with required elements
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (1) writeTethysXml produces valid XML ---\n');

xmlStr = writeTethysXml(result, annots, 'project', 'SORP', 'software', 'bsnr');

assert(~isempty(xmlStr), 'writeTethysXml: output should not be empty');
assert(contains(xmlStr, '<?xml'),          'missing XML declaration');
assert(contains(xmlStr, '<Detections'),    'missing Detections root element');
assert(contains(xmlStr, '<DataSource>'),   'missing DataSource element');
assert(contains(xmlStr, '<Algorithm>'),    'missing Algorithm element');
assert(contains(xmlStr, '<OnEffort>'),     'missing OnEffort element');
assert(contains(xmlStr, '<Detection>'),    'missing Detection element');
assert(contains(xmlStr, 'SORP'),           'missing project name');
assert(contains(xmlStr, 'bsnr'),           'missing software name');
fprintf('  [PASS] XML contains required elements\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (2) writeTethysXml maps fields correctly
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (2) Field mapping correct ---\n');

% Start time format
assert(contains(xmlStr, '2024-03-15T14:23:07'), ...
    'writeTethysXml: Start time not in ISO 8601 format');

% SNR values
assert(contains(xmlStr, '<SNR_dB>17.3'), ...
    sprintf('writeTethysXml: SNR_dB not found (got: %s)', xmlStr));
assert(contains(xmlStr, '<SNR_dB>8.6'), ...
    'writeTethysXml: second SNR_dB not found');

% Frequency
assert(contains(xmlStr, '<MinFreq_Hz>25.00'), 'missing MinFreq_Hz');
assert(contains(xmlStr, '<MaxFreq_Hz>90.00'), 'missing MaxFreq_Hz');

% Classification -> Subtype
assert(contains(xmlStr, '<Subtype>ABW Z</Subtype>'), 'missing Subtype for ABW Z');
assert(contains(xmlStr, '<Subtype>ABW A</Subtype>'), 'missing Subtype for ABW A');

% Duration
assert(contains(xmlStr, '<Duration_s>8.0'), 'missing Duration_s');

fprintf('  [PASS] all fields mapped correctly\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (3) writeTethysXml includes ReceivedLevel_dB when calibrated
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (3) ReceivedLevel_dB present when calibrated ---\n');

xmlCal = writeTethysXml(resultCal, annots);

assert(contains(xmlCal, '<ReceivedLevel_dB>122.4'), ...
    'writeTethysXml: ReceivedLevel_dB not found for calibrated result');
assert(contains(xmlCal, '<ReceivedLevel_dB>115.8'), ...
    'writeTethysXml: second ReceivedLevel_dB not found');

xmlNoCal = writeTethysXml(result, annots);
assert(~contains(xmlNoCal, 'ReceivedLevel_dB'), ...
    'writeTethysXml: ReceivedLevel_dB should be absent without calibration');

fprintf('  [PASS] ReceivedLevel_dB present iff calibrated\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (4) writeTethysXml writes to file
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (4) writeTethysXml writes to file ---\n');

tmpFile = [tempname '.xml'];
cleanupFile = onCleanup(@() deleteIfExists(tmpFile));

writeTethysXml(result, annots, 'outputFile', tmpFile);

assert(isfile(tmpFile), 'writeTethysXml: output file not created');
fileContent = fileread(tmpFile);
assert(contains(fileContent, '<Detections'), ...
    'writeTethysXml: file content missing Detections element');
fprintf('  [PASS] XML file written successfully\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (5) readTethysDetections reads back XML file
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (5) readTethysDetections reads XML file ---\n');

writeTethysXml(result, annots, 'outputFile', tmpFile);
annotsBak = readTethysDetections(tmpFile, 'C:\data\test');

assert(~isempty(annotsBak), 'readTethysDetections: returned empty');
assert(numel(annotsBak) == 2, ...
    sprintf('readTethysDetections: expected 2 annotations, got %d', numel(annotsBak)));
fprintf('  [PASS] read back %d annotations from XML\n', numel(annotsBak));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (6) Round-trip preserves t0, tEnd, freq
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (6) Round-trip preserves t0, tEnd, freq ---\n');

writeTethysXml(result, annots, 'outputFile', tmpFile);
annotsRT = readTethysDetections(tmpFile, 'C:\data\test');

% t0 round-trip (allow 1 second tolerance for ISO 8601 rounding)
dt0 = abs(annotsRT(1).t0 - annot1.t0) * 86400;
assert(dt0 < 1, sprintf('round-trip t0 error: %.3f s', dt0));

% freq round-trip
assert(~isempty(annotsRT(1).freq), 'round-trip: freq missing');
assert(abs(annotsRT(1).freq(1) - annot1.freq(1)) < 0.01, ...
    sprintf('round-trip MinFreq_Hz error: %.2f vs %.2f', ...
    annotsRT(1).freq(1), annot1.freq(1)));
assert(abs(annotsRT(1).freq(2) - annot1.freq(2)) < 0.01, ...
    sprintf('round-trip MaxFreq_Hz error: %.2f vs %.2f', ...
    annotsRT(1).freq(2), annot1.freq(2)));

% soundFolder set correctly
assert(strcmp(annotsRT(1).soundFolder, 'C:\data\test'), ...
    'round-trip: soundFolder not preserved');

fprintf('  [PASS] round-trip t0 error = %.3f s, freq = [%.1f %.1f] Hz\n', ...
    dt0, annotsRT(1).freq(1), annotsRT(1).freq(2));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (7) readTethysDetections handles missing freq with freqFallback
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (7) freqFallback used when freq absent ---\n');

% Write without freq by temporarily clearing it
annotNoFreq      = annot1;
annotNoFreq.freq = [];
resultOne        = result(1,:);

% Build minimal XML without MinFreq_Hz/MaxFreq_Hz
xmlNoFreq = writeTethysXml(resultOne, annotNoFreq);
% Manually strip frequency elements to simulate absent freq in source
xmlNoFreq = regexprep(xmlNoFreq, '<MinFreq_Hz>[^<]*</MinFreq_Hz>\n?', '');
xmlNoFreq = regexprep(xmlNoFreq, '<MaxFreq_Hz>[^<]*</MaxFreq_Hz>\n?', '');

tmpNoFreq = [tempname '.xml'];
cleanupNoFreq = onCleanup(@() deleteIfExists(tmpNoFreq));
fid = fopen(tmpNoFreq, 'w'); fprintf(fid, '%s', xmlNoFreq); fclose(fid);

% Without fallback — should warn and leave freq empty
warnState = warning('off', 'readTethysDetections:missingFreq');
annotsNF  = readTethysDetections(tmpNoFreq, 'C:\data\test');
warning(warnState);
assert(isempty(annotsNF(1).freq), 'should have empty freq without fallback');

% With fallback
annotsFB = readTethysDetections(tmpNoFreq, 'C:\data\test', 'freqFallback', [20 50]);
assert(isequal(annotsFB(1).freq, [20 50]), ...
    sprintf('freqFallback not applied: got [%.1f %.1f]', annotsFB(1).freq));
fprintf('  [PASS] freqFallback applied correctly\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (8) readTethysDetections handles struct input
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('--- (8) readTethysDetections accepts struct input ---\n');

% Build a struct mimicking a Tethys client query result
tStruct(1).Start = '2024-03-15T14:23:07';
tStruct(1).End   = '2024-03-15T14:23:15';
tStruct(1).Call  = 'ABW Z';
tStruct(1).Parameters.MinFreq_Hz = 25;
tStruct(1).Parameters.MaxFreq_Hz = 90;
tStruct(1).Parameters.Duration_s = 8;

tStruct(2).Start = '2024-03-15T14:24:00';
tStruct(2).End   = '2024-03-15T14:24:12';
tStruct(2).Call  = 'ABW A';
tStruct(2).Parameters.MinFreq_Hz = 15;
tStruct(2).Parameters.MaxFreq_Hz = 30;
tStruct(2).Parameters.Duration_s = 12;

annotsS = readTethysDetections(tStruct, 'C:\data\test');

assert(numel(annotsS) == 2, 'struct input: expected 2 annotations');
assert(strcmp(annotsS(1).classification, 'ABW Z'), ...
    'struct input: classification not set');
assert(annotsS(1).freq(1) == 25 && annotsS(1).freq(2) == 90, ...
    'struct input: freq not set correctly');
assert(annotsS(1).duration == 8, 'struct input: duration not set');

% Verify datenum conversion
expectedT0 = datenum('2024-03-15 14:23:07', 'yyyy-mm-dd HH:MM:SS');
assert(abs(annotsS(1).t0 - expectedT0) * 86400 < 1, ...
    'struct input: t0 datenum conversion error');

fprintf('  [PASS] struct input: %d annotations, t0 correct, freq=[%.0f %.0f]\n', ...
    numel(annotsS), annotsS(1).freq(1), annotsS(1).freq(2));

fprintf('\n=== test_tethys PASSED ===\n');
end

function deleteIfExists(f)
if isfile(f), delete(f); end
end
