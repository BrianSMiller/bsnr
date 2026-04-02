function [annot, metadata, cleanup] = createCalibratedTestFixture(varargin)
% Create a WAV fixture with a known acoustic source level for calibration testing.
%
% Generates a tone in band-limited noise where both signal and noise levels
% are specified in dB re 1 µPa. The audio is scaled through the instrument
% signal chain (hydrophone sensitivity, frontend gain, ADC full-scale) to
% produce a WAV file in dBFS, exactly as a real recording would appear.
%
% The metadata struct matches the real-world format used by snrEstimate
% and applyCalibration (see e.g. metaDataKerguelen2024.m).
%
% INPUTS (name-value pairs)
%   signalLeveldB   Source level in dB re 1 µPa RMS  (default: 122)
%   noiseLeveldB    Noise level in dB re 1 µPa RMS   (default:  90)
%   toneFreqHz      Tone frequency in Hz              (default: 100)
%   freq            [lowHz highHz] annotation band    (default: [80 120])
%   durationSec     Detection duration in seconds     (default: 4)
%   classification  Label string                      (default: '')
%
% OUTPUTS
%   annot      Annotation struct ready for snrEstimate
%   metadata   Instrument metadata struct (Kerguelen 2024 front-end)
%   cleanup    Function handle: cleanup() deletes the temp WAV folder
%
% METADATA (hardcoded, matching AAD Kerguelen 2024 whale recorder)
%   hydroSensitivity_dB  -165.9  dB re V/µPa
%   adPeakVolt            1.5    V  (3 V peak-to-peak, 16-bit ADC)
%   sampleRate           12000   Hz
%   frontEndGain_dB      [9.28 15.55 18.47 19.58 19.95 20.01 20.03 20.03 20.04 20.04 12.27 -23.91 -60.10]
%   frontEndFreq_Hz      [2 5 10 20 50 100 200 500 1000 2000 5000 10000 20000]

o = inputParser;
addParameter(o, 'signalLeveldB',  122,         @isnumeric);
addParameter(o, 'noiseLeveldB',    90,         @isnumeric);
addParameter(o, 'toneFreqHz',     100,         @isnumeric);
addParameter(o, 'freq',           [80 120],    @isnumeric);
addParameter(o, 'durationSec',      4,         @isnumeric);
addParameter(o, 'classification',  '',         @ischar);
parse(o, varargin{:});
p = o.Results;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Metadata struct (Kerguelen 2024 front-end)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

metadata.hydroSensitivity_dB = -165.9;
metadata.adPeakVolt          = 1.5;
metadata.sampleRate          = 12000;
metadata.frontEndFreq_Hz     = [2 5 10 20 50 100 200 500 1000 2000 5000 10000 20000];
metadata.frontEndGain_dB     = [9.28 15.55 18.47 19.58 19.95 20.01 20.03 20.03 20.04 20.04 12.27 -23.91 -60.10];

sampleRate = metadata.sampleRate;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Convert acoustic levels to dBFS then to linear WAV amplitude
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Frontend gain at tone frequency (interpolate on log-freq axis)
gainAtTone = interp1(log10(metadata.frontEndFreq_Hz), metadata.frontEndGain_dB, ...
    log10(p.toneFreqHz), 'linear', 'extrap');

% Physical signal chain (amplitude domain):
%   dBFS = dB_re_1uPa + hydroSensitivity_dB + frontEndGain_dB - 20*log10(adPeakVolt)
% signalRMS: WAV amplitude of the tone.
% noiseRMS:  target IN-BAND noise RMS in WAV units. Background noise is then
%            scaled to wideband white noise that achieves this in-band level
%            (see widebandRMS below).
adPeakdBV  = 20 * log10(metadata.adPeakVolt);
signalDBFS = p.signalLeveldB + metadata.hydroSensitivity_dB + gainAtTone - adPeakdBV;
noiseDBFS  = p.noiseLeveldB  + metadata.hydroSensitivity_dB + gainAtTone - adPeakdBV;
signalRMS  = 10^(signalDBFS / 20);
noiseRMS   = 10^(noiseDBFS  / 20);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Generate audio
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Buffer matches createTestFixture: half-duration + spectroBuffer + safetyBuffer
% This ensures the noise window fits within the file when using the full
% snrEstimate pipeline with noiseDelay=0 and pre/post=1.
spectroBuffer = 1;
safetyBuffer  = 2;
bufferSec  = 0.5 * p.durationSec + spectroBuffer + safetyBuffer;
totalSec   = p.durationSec + 2 * bufferSec;
nTotal     = round(totalSec * sampleRate);
detOffset  = round(bufferSec * sampleRate) + 1;
detEnd     = detOffset + round(p.durationSec * sampleRate) - 1;

rng(42);

% Band-limited noise: scale white noise so in-band RMS = noiseRMS
nyquist   = sampleRate / 2;
bandwidth = diff(p.freq);
if bandwidth > 0 && bandwidth < nyquist
    widebandRMS = noiseRMS * sqrt(nyquist / bandwidth);
else
    widebandRMS = noiseRMS;
end
audio = widebandRMS * randn(nTotal, 1);

% Add a pure tone at toneFreqHz to the signal window.
% signalRMS is the RMS pressure level converted to WAV units.
% A sine wave sin(2*pi*f*t) has RMS = 1/sqrt(2), so we multiply
% by sqrt(2) to get a sine whose RMS equals signalRMS.
tTone = (0 : detEnd - detOffset)' / sampleRate;
audio(detOffset:detEnd) = audio(detOffset:detEnd) + ...
    signalRMS * sqrt(2) * sin(2 * pi * p.toneFreqHz * tTone);

% Do NOT normalise by audioPeak here — unlike createTestFixture, this
% fixture is used for absolute level calibration tests where the signal
% amplitude must be precisely controlled. Peak normalisation would destroy
% the known signal level.
% Instead, warn if clipping would occur so the caller can adjust levels.
audioPeak = max(abs(audio));
if audioPeak > 0.99
    warning('createCalibratedTestFixture:clipping', ...
        ['Audio peak %.3f would clip — reduce signalLeveldB or noiseLeveldB. ' ...
         'No normalisation applied; results will be invalid.'], audioPeak);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Write WAV and build annotation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

tmpDir = fullfile(tempdir, sprintf('annotSNR_cal_%s', ...
    datestr(now, 'yyyymmdd_HHMMSS_FFF')));
mkdir(tmpDir);
fileStart = floor(now() * 86400) / 86400;
wavPath   = fullfile(tmpDir, [datestr(fileStart, 'yyyy-mm-dd_HH-MM-SS') '.wav']);
audiowrite(wavPath, audio, sampleRate);
cleanup = @() rmdir(tmpDir, 's');

annot.soundFolder    = tmpDir;
annot.t0             = fileStart + bufferSec              / 86400;
annot.tEnd           = fileStart + (bufferSec + p.durationSec) / 86400;
annot.duration       = p.durationSec;
annot.freq           = p.freq;
annot.channel        = 1;
if ~isempty(p.classification)
    annot.classification = p.classification;
else
    annot.classification = sprintf('Cal: %d dB signal, %d dB noise @ %d Hz', ...
        round(p.signalLeveldB), round(p.noiseLeveldB), round(p.toneFreqHz));
end

end
