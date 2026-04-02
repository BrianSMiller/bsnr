function [annot, cleanupFn] = createTestFixture(varargin)
% Create a temporary WAV file and matching annotation struct for testing.
%
% Writes a real WAV file to a subfolder of tempdir with a timestamp
% filename that wavFolderInfo can parse, and returns an annotation struct
% with all fields required by snrEstimate.
%
% USAGE
%   [annot, cleanupFn] = createTestFixture()
%   [annot, cleanupFn] = createTestFixture('sampleRate', 2000, ...)
%
% OPTIONAL NAME-VALUE INPUTS
%   sampleRate    Sample rate in Hz          (default: 2000)
%   durationSec   Detection duration in s    (default: 10)
%   toneFreqHz    Tone frequency in Hz       (default: 200)
%   signalRMS     Tone RMS amplitude         (default: 1.0)
%   noiseRMS      Target in-band noise RMS amplitude (default: 0.1).
%                 White noise is generated with wideband RMS scaled up
%                 by sqrt(Nyquist/bandwidth) so that the in-band power
%                 equals noiseRMS^2. This keeps noise spectrally flat
%                 (realistic) while ensuring consistent in-band SNR
%                 across all methods.
%   freq          [lowHz highHz] freq band   (default: [150 250])
%   channel       Channel index              (default: 1)
%
% OUTPUTS
%   annot       Annotation struct with fields:
%                 .soundFolder  path to temp WAV folder
%                 .t0           datenum start of detection
%                 .tEnd         datenum end of detection
%                 .duration     detection duration in seconds
%                 .freq         [lowHz highHz]
%                 .channel      channel index
%   cleanupFn   Function handle — call cleanupFn() to delete temp files.
%
% WAV files are named using the default wavFolderInfo/readWavHeader format:
%   yyyy-mm-dd_HH-MM-SS.wav
%
% The WAV is long enough to contain the detection window plus half-duration
% noise buffers on each side (the 'beforeAndAfter' default noise strategy).

p = inputParser;
addParameter(p, 'sampleRate',  2000);
addParameter(p, 'durationSec', 10);
addParameter(p, 'toneFreqHz',  200);
addParameter(p, 'signalRMS',   1.0);
addParameter(p, 'noiseRMS',    0.1);
addParameter(p, 'freq',        [150 250]);
addParameter(p, 'channel',        1);
addParameter(p, 'classification', '');
parse(p, varargin{:});
o = p.Results;

sampleRate  = o.sampleRate;
detDuration = o.durationSec;

% Build a WAV long enough for:
%   - noise window: 0.5*duration before and after the detection
%   - spectroAnnotationAndNoise pre/post buffers: default 1 s each
%   - extra safety margin: 2 s each end
spectroBuffer = 1;   % matches default spectroParams.pre/post
safetyBuffer  = 2;
bufferSec     = 0.5*detDuration + spectroBuffer + safetyBuffer;
totalSec      = bufferSec + detDuration + bufferSec;
nTotal        = round(totalSec * sampleRate);
detOffsetSec  = bufferSec;

rng(42);

% Generate white noise scaled so that its in-band RMS equals noiseRMS.
% White noise power is uniformly distributed across [0, Nyquist], so the
% in-band fraction is bandwidth/Nyquist and the wideband RMS needed to
% achieve a target in-band RMS is: wideband = noiseRMS * sqrt(Nyquist/bw).
% This keeps the noise wideband (realistic background) while ensuring all
% SNR methods — which integrate only within the annotation band — see the
% intended in-band SNR.
nyquist      = sampleRate / 2;
bandwidth    = diff(o.freq);
if bandwidth > 0 && bandwidth < nyquist
    widebandRMS = o.noiseRMS * sqrt(nyquist / bandwidth);
else
    widebandRMS = o.noiseRMS;
end
audio = widebandRMS * randn(nTotal, 1);

toneStart = round(detOffsetSec * sampleRate) + 1;
toneEnd   = round((detOffsetSec + detDuration) * sampleRate);
tTone     = (0 : toneEnd-toneStart)' / sampleRate;
audio(toneStart:toneEnd) = audio(toneStart:toneEnd) + ...
    o.signalRMS * sin(2 * pi * o.toneFreqHz * tTone);

% Scale to avoid audiowrite clipping (guard against all-zero audio)
audioPeak = max(abs(audio));
if audioPeak > 0
    audio = audio * (0.9 / audioPeak);
end

% Write to a uniquely-named temp folder
tmpDir = fullfile(tempdir, sprintf('annotSNR_test_%s', ...
    datestr(now, 'yyyymmdd_HHMMSS_FFF')));
mkdir(tmpDir);

% Truncate to whole seconds so the filename and datenum are consistent.
% now() has sub-second precision but the filename format only has 1 s
% resolution — without truncation, readWavHeader parses a slightly
% earlier time from the filename, shifting the detection window off
% the tone burst in the audio.
fileStartDatenum = floor(now() * 86400) / 86400;   % truncate to 1 s
fileStartStr     = datestr(fileStartDatenum, 'yyyy-mm-dd_HH-MM-SS');
wavPath          = fullfile(tmpDir, [fileStartStr '.wav']);
audiowrite(wavPath, audio, sampleRate);

% Build annotation struct
annot.soundFolder = tmpDir;
annot.t0          = fileStartDatenum + detOffsetSec              / 86400;
annot.tEnd        = fileStartDatenum + (detOffsetSec+detDuration) / 86400;
annot.duration    = detDuration;
annot.freq        = o.freq;
annot.channel         = o.channel;
if ~isempty(o.classification)
    annot.classification = o.classification;
end

cleanupFn = @() rmdir(tmpDir, 's');

end
