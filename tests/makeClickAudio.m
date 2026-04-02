function [sigWithClicks, sigClean, noiseAudio, clickSamples] = makeClickAudio( ...
    sampleRate, durationSec, toneFreqHz, signalRMS, noiseRMS, ...
    clickIntervalSec, clickAmplitude)
% Generate tone-in-noise with embedded echosounder-like clicks.
%
% Produces two signal arrays: one with clicks (for testing that clicks
% degrade SNR estimates) and one clean (for regression testing that
% removeClicks does not distort clean signals). An independent noise-only
% array is also returned for use as the noise reference.
%
% Click model: rectangular pulses of 1 ms duration at regular intervals,
% amplitude well above the noise floor so removeClicks(audio, 3, 1000)
% reliably suppresses them.
%
% INPUTS
%   sampleRate        Sample rate in Hz              (default: 2000)
%   durationSec       Duration of each segment (s)   (default: 10)
%   toneFreqHz        Tone frequency in Hz            (default: 200)
%   signalRMS         RMS amplitude of tone           (default: 1.0)
%   noiseRMS          RMS amplitude of Gaussian noise (default: 0.1)
%   clickIntervalSec  Interval between clicks (s)     (default: 1.0)
%   clickAmplitude    Peak amplitude of each click    (default: 10.0)
%                     Should be >> threshold * std(audio) to be detected.
%                     With threshold=3 and noiseRMS=0.1, std ≈ 0.1,
%                     so thresh ≈ 0.3 — clicks at 10.0 are easily caught.
%
% OUTPUTS
%   sigWithClicks  Tone + noise + clicks (column vector)
%   sigClean       Tone + noise, no clicks (column vector)
%   noiseAudio     Independent noise-only segment (column vector)
%   clickSamples   Sample indices of click centres (for verification)

if nargin < 1 || isempty(sampleRate),       sampleRate       = 2000; end
if nargin < 2 || isempty(durationSec),      durationSec      = 10;   end
if nargin < 3 || isempty(toneFreqHz),       toneFreqHz       = 200;  end
if nargin < 4 || isempty(signalRMS),        signalRMS        = 1.0;  end
if nargin < 5 || isempty(noiseRMS),         noiseRMS         = 0.1;  end
if nargin < 6 || isempty(clickIntervalSec), clickIntervalSec = 1.0;  end
if nargin < 7 || isempty(clickAmplitude),   clickAmplitude   = 50.0; end

rng(77);
nSamples   = round(durationSec * sampleRate);
t          = (0 : nSamples-1)' / sampleRate;

tone       = signalRMS * sin(2 * pi * toneFreqHz * t);
noise      = noiseRMS  * randn(nSamples, 1);
sigClean   = tone + noise;
noiseAudio = noiseRMS  * randn(nSamples, 1);

% Build click train: sine bursts at toneFreqHz so they pass through the
% bandpass filter used by snrTimeDomain. Rectangular pulses are broadband
% and lose most of their energy after bandpass filtering.
clickDurSamples = max(2, round(0.005 * sampleRate));   % 5 ms sine burst
clickTimes      = clickIntervalSec : clickIntervalSec : durationSec - clickIntervalSec;
clickSamples    = round(clickTimes * sampleRate);
clickSamples    = clickSamples(clickSamples > 0 & clickSamples + clickDurSamples <= nSamples);

clicks = zeros(nSamples, 1);
tClick = (0 : clickDurSamples-1)' / sampleRate;
clickBurst = clickAmplitude * sin(2 * pi * toneFreqHz * tClick);
for k = 1:numel(clickSamples)
    idx = clickSamples(k) : clickSamples(k) + clickDurSamples - 1;
    clicks(idx) = clickBurst;
end

sigWithClicks = sigClean + clicks;

end
