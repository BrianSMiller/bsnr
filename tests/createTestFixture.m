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
%   signalType    Signal type:               (default: 'tone')
%                   'tone'     - single continuous tone at toneFreqHz
%                   'bioduck'  - repeated FM downsweeps mimicking Antarctic
%                                minke whale bio-duck calls (A1 type by default).
%                                Uses freqHigh, freqLow, pulseDuration,
%                                pulseInterval, pulsesPerSeries, seriesInterval.
%   toneFreqHz    Tone frequency in Hz       (default: 200)
%                   For 'bioduck': start frequency of each downsweep.
%   freqHigh         Downsweep start freq Hz    (default: 200) [bioduck only]
%   freqLow          Downsweep end freq Hz      (default: 60)  [bioduck only]
%   pulseDuration    Pulse duration in s        (default: 0.10)[bioduck only]
%   pulseInterval    IPI start-to-start in s    (default: 0.30)[bioduck only]
%   pulsesPerSeries  Pulses per series          (default: 4)   [bioduck only]
%   seriesInterval   ISI end-to-start in s      (default: 3.10)[bioduck only]
%                    Parameters based on Dominello & Sirovic (2016) A1 call type.
%   signalRMS     Tone RMS amplitude         (default: 1.0)
%   noiseRMS      Target in-band noise RMS amplitude (default: 0.1).
%                 White noise is generated with wideband RMS scaled up
%                 by sqrt(Nyquist/bandwidth) so that the in-band power
%                 equals noiseRMS^2. This keeps noise spectrally flat
%                 (realistic) while ensuring consistent in-band SNR
%                 across all methods.
%   freq          [lowHz highHz] freq band   (default: [150 250] for tone,
%                                             [40 110] for bioduck)
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
% NOTES
%   The bio-duck fixture produces a bout of repeated FM downsweeps spanning
%   the full durationSec window. The annotation covers the entire bout, as
%   is typical in practice where analysts draw a single box around the
%   whole bout rather than individual pulses. The noise window therefore
%   samples audio adjacent to the bout, which may itself contain other
%   bouts in real recordings — a key challenge this fixture is designed to
%   expose in SNR method testing.
%
%   Bio-duck parameters are based on Risch et al. (2014) Biology Letters
%   doi:10.1098/rsbl.2014.0175 and Dominello & Sirovic (2016).
%
% WAV files are named using the default wavFolderInfo/readWavHeader format:
%   yyyy-mm-dd_HH-MM-SS.wav
%
% The WAV is long enough to contain the detection window plus half-duration
% noise buffers on each side (the 'beforeAndAfter' default noise strategy).

p = inputParser;
addParameter(p, 'sampleRate',    2000);
addParameter(p, 'durationSec',     10);
addParameter(p, 'signalType',      'tone');
addParameter(p, 'toneFreqHz',      200);
addParameter(p, 'freqHigh',        200);   % bioduck sweep start Hz (A1: ~200 Hz)
addParameter(p, 'freqLow',         60);    % bioduck sweep end Hz   (A1: ~60 Hz)
addParameter(p, 'pulseDuration',   0.10);  % pulse duration s       (Risch 2014: mean 0.1 s)
addParameter(p, 'pulseInterval',   0.30);  % IPI start-to-start s   (Dominello 2016 A1: ~0.3 s)
addParameter(p, 'pulsesPerSeries', 4);     % pulses per series      (A1: 4)
addParameter(p, 'seriesInterval',  3.10);  % ISI end-to-start s     (Risch 2014: 3.1 s)
addParameter(p, 'signalRMS',     1.0);
addParameter(p, 'noiseRMS',      0.1);
addParameter(p, 'freq',          []);    % [] = auto-set by signalType
addParameter(p, 'channel',       1);
addParameter(p, 'classification', '');
parse(p, varargin{:});
o = p.Results;

% Auto-set freq band if not specified
if isempty(o.freq)
    if strcmpi(o.signalType, 'bioduck')
        o.freq = [30 500];   % matches plotParams('bioduck')
    else
        o.freq = [150 250];
    end
end

sampleRate  = o.sampleRate;
detDuration = o.durationSec;

% Build a WAV long enough for:
%   - noise window: 0.5*duration before and after the detection
%   - spectroAnnotationAndNoise pre/post buffers: default 1 s each
%   - extra safety margin: 2 s each end
spectroBuffer = 1;
safetyBuffer  = 2;
bufferSec     = 0.5*detDuration + spectroBuffer + safetyBuffer;
totalSec      = bufferSec + detDuration + bufferSec;
nTotal        = round(totalSec * sampleRate);
detOffsetSec  = bufferSec;

rng(42);

% Generate white noise scaled so in-band RMS equals noiseRMS
nyquist      = sampleRate / 2;
bandwidth    = diff(o.freq);
if bandwidth > 0 && bandwidth < nyquist
    widebandRMS = o.noiseRMS * sqrt(nyquist / bandwidth);
else
    widebandRMS = o.noiseRMS;
end
audio = widebandRMS * randn(nTotal, 1);

% Generate signal and add to detection window
toneStart = round(detOffsetSec * sampleRate) + 1;
toneEnd   = round((detOffsetSec + detDuration) * sampleRate);

switch lower(o.signalType)
    case 'tone'
        tTone = (0 : toneEnd-toneStart)' / sampleRate;
        audio(toneStart:toneEnd) = audio(toneStart:toneEnd) + ...
            o.signalRMS * sin(2 * pi * o.toneFreqHz * tTone);

    case 'bioduck'
        % Repeated FM downsweeps modelled on Antarctic minke whale bio-duck
        % call type A1 (Dominello & Sirovic 2016, Mar. Mam. Sci. 32:826-838).
        %
        % A1 structure:
        %   4 pulses per series, each sweeping ~200->60 Hz over ~0.1 s
        %   IPI (inter-pulse interval, start-to-start): ~0.3 s
        %   ISI (inter-series interval, end-to-start of next series): ~3.1 s
        %   Peak frequency: 130-150 Hz
        %
        % The annotation covers the full bout (multiple series), as analysts
        % draw a single box rather than annotating individual pulses or series.
        %
        % Parameters based on:
        %   Dominello & Sirovic (2016) doi:10.1111/mms.12302
        %   Risch et al. (2014) doi:10.1098/rsbl.2014.0175

        nPulseSamples    = round(o.pulseDuration  * sampleRate);
        ipiSamples       = round(o.pulseInterval  * sampleRate);  % start-to-start
        isiSamples       = round(o.seriesInterval * sampleRate);  % end-of-last-pulse to start-of-next
        nPulsesPerSeries = o.pulsesPerSeries;

        % Build one FM downsweep pulse using chirp-phase instantaneous frequency
        tPulse = (0 : nPulseSamples-1)' / sampleRate;
        fStart = o.freqHigh;
        fEnd   = o.freqLow;
        k      = (fEnd - fStart) / o.pulseDuration;
        phase  = 2 * pi * (fStart * tPulse + 0.5 * k * tPulse.^2);
        pulse  = o.signalRMS * sin(phase);

        % Place series of pulses across the detection window
        pos = toneStart;
        while pos <= toneEnd
            % Place nPulsesPerSeries pulses at IPI spacing
            for ip = 1:nPulsesPerSeries
                if pos + nPulseSamples - 1 > toneEnd, break; end
                idx = pos : pos + nPulseSamples - 1;
                audio(idx) = audio(idx) + pulse;
                pos = pos + ipiSamples;
            end
            % Advance by ISI after the last pulse ends
            pos = pos + isiSamples;
        end

    otherwise
        error('createTestFixture:unknownSignalType', ...
            'Unknown signalType ''%s''. Use ''tone'' or ''bioduck''.', ...
            o.signalType);
end

% Scale to avoid audiowrite clipping
audioPeak = max(abs(audio));
if audioPeak > 0
    audio = audio * (0.9 / audioPeak);
end

% Write to a uniquely-named temp folder.
% tempname() is guaranteed unique by the OS, avoiding collisions when
% multiple fixtures are created in rapid succession.
tmpDir = tempname();
mkdir(tmpDir);

fileStartDatenum = floor(now() * 86400) / 86400;
fileStartStr     = datestr(fileStartDatenum, 'yyyy-mm-dd_HH-MM-SS');
wavPath          = fullfile(tmpDir, [fileStartStr '.wav']);
audiowrite(wavPath, audio, sampleRate);

% Build annotation struct
annot.soundFolder = tmpDir;
annot.t0          = fileStartDatenum + detOffsetSec               / 86400;
annot.tEnd        = fileStartDatenum + (detOffsetSec + detDuration) / 86400;
annot.duration    = detDuration;
annot.freq        = o.freq;
annot.channel     = o.channel;
if ~isempty(o.classification)
    annot.classification = o.classification;
end

cleanupFn = @() rmdir(tmpDir, 's');

end
