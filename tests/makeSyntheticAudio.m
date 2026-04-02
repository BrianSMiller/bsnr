function [sigAudio, noiseAudio, trueSNRdB] = makeSyntheticAudio( ...
    sampleRate, durationSec, toneFreqHz, signalRMS, noiseRMS)
% Generate synthetic audio with a known, analytically verifiable SNR.
%
% Produces a tone-in-noise signal and an independent noise-only segment at
% controlled RMS levels. The true SNR is the simple power ratio in dB:
%   trueSNRdB = 10 * log10(signalRMS^2 / noiseRMS^2)
%
% For SNR method tests, use long durations (>= 5 s) and stationary noise
% so that the Lurton estimator converges towards the true power ratio.
%
% INPUTS
%   sampleRate   Sample rate in Hz              (e.g. 2000)
%   durationSec  Duration of each segment (s)   (e.g. 10)
%   toneFreqHz   Pure tone frequency in Hz       (e.g. 200)
%   signalRMS    RMS amplitude of tone           (e.g. 1.0)
%   noiseRMS     RMS amplitude of Gaussian noise (e.g. 0.1)
%
% OUTPUTS
%   sigAudio    Tone + noise, column vector, length = durationSec*sampleRate
%   noiseAudio  Noise only,  column vector, same length
%   trueSNRdB   10*log10(signalRMS^2 / noiseRMS^2)
%
% Noise is seeded for reproducibility across test runs.

rng(42);
nSamples   = round(durationSec * sampleRate);
t          = (0 : nSamples-1)' / sampleRate;
tone       = signalRMS * sin(2 * pi * toneFreqHz * t);
noise      = noiseRMS  * randn(nSamples, 1);

sigAudio   = tone + noise;
noiseAudio = noiseRMS * randn(nSamples, 1);
trueSNRdB  = 10 * log10(signalRMS^2 / noiseRMS^2);

end
