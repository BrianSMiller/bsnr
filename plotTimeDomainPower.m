function plotTimeDomainPower(clipAudio, clipT0, detection, noise, ...
    freq, sampleRate, rmsSignal, rmsNoise, noiseVar)
% Plot bandpass-filtered instantaneous power for a detection clip.
%
% Draws into the current axes (gca). Time axis matches the spectrogram
% layout: clip starts at t=0, signal and noise windows are annotated with
% coloured lines and text labels, consistent with spectroAnnotationAndNoise.
%
% The full clip (noise before + signal + noise after) is filtered as one
% continuous waveform, avoiding the discontinuity that results from
% filtering signal and noise separately.
%
% INPUTS
%   clipAudio   Full audio clip (column vector): spans from noise window
%               start (minus pre buffer) to noise window end (plus post
%               buffer). Must be continuous — no excluded samples.
%   clipT0      Matlab datenum of the clip start (first sample of clipAudio)
%   detection   Struct with fields .t0, .tEnd, .rmsLevel, and optionally
%               .classification (string) and .t0 for the title
%   noise       Struct with fields .t0, .tEnd, .rmsLevel
%   freq        [lowHz highHz] bandpass filter cutoff frequencies
%   sampleRate  Sample rate in Hz
%   rmsSignal   Mean instantaneous power of filtered signal window
%   rmsNoise    Mean instantaneous power of filtered noise window
%   noiseVar    Variance of instantaneous power in noise window

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Filter full clip
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

try
    d       = designfilt('bandpassfir', 'FilterOrder', 48, ...
        'CutoffFrequency1', freq(1), 'CutoffFrequency2', freq(2), ...
        'SampleRate', sampleRate);
    clipFilt = filtfilt(d, clipAudio);
catch
    warning('plotTimeDomainPower:filterFailed', 'Bandpass filter failed.');
    return
end

power = clipFilt.^2;
nSamp = length(clipAudio);
tClip = (0 : nSamp-1)' / sampleRate;   % seconds from clip start

% Convert datenums to seconds-from-clip-start
tOffset = @(dn) (dn - clipT0) * 86400;

tSigStart   = tOffset(detection.t0);
tSigEnd     = tOffset(detection.tEnd);
tNoiseStart = tOffset(noise.t0);
tNoiseEnd   = tOffset(noise.tEnd);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Plot
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Background trace in light grey
plot(tClip, power, 'color', [0.7 0.7 0.7], 'linewidth', 0.5);
hold on

% Highlight noise window in dark red
noiseIx = tClip >= tNoiseStart & tClip <= tNoiseEnd & ...
         ~(tClip >= tSigStart  & tClip <= tSigEnd);
plot(tClip(noiseIx), power(noiseIx), 'color', [0.5 0 0], 'linewidth', 1);

% Highlight signal window in dark green
sigIx = tClip >= tSigStart & tClip <= tSigEnd;
plot(tClip(sigIx), power(sigIx), 'color', [0 0.5 0], 'linewidth', 1.5);

% RMS level lines
xLim = xlim;
plot([tNoiseStart tSigStart],   rmsNoise  * [1 1], 'r', 'linewidth', 2);
plot([tSigEnd     tNoiseEnd],   rmsNoise  * [1 1], 'r', 'linewidth', 2);
plot([tSigStart   tSigEnd],     rmsSignal * [1 1], 'g', 'linewidth', 2);

% One-sided errorbar for noise std dev (power is always positive)
noiseStd = sqrt(noiseVar);
line([tNoiseStart tNoiseStart], [rmsNoise rmsNoise + noiseStd], ...
    'color', 'k', 'linewidth', 2);
line([tNoiseStart - diff(xLim)*0.01, tNoiseStart + diff(xLim)*0.01], ...
    [rmsNoise + noiseStd, rmsNoise + noiseStd], 'color', 'k', 'linewidth', 2);

% Window boundary markers
yLim = ylim;
line([tSigStart   tSigStart],   yLim, 'color', [0 0.5 0], 'linewidth', 1, 'linestyle', '--');
line([tSigEnd     tSigEnd],     yLim, 'color', [0 0.5 0], 'linewidth', 1, 'linestyle', '--');
line([tNoiseStart tNoiseStart], yLim, 'color', [0.5 0 0], 'linewidth', 1, 'linestyle', '--');
line([tNoiseEnd   tNoiseEnd],   yLim, 'color', [0.5 0 0], 'linewidth', 1, 'linestyle', '--');

% Text labels instead of legend
text(tSigStart, rmsSignal, sprintf('  Signal = %.1f dBFS', detection.rmsLevel), ...
    'color', 'k', 'verticalAlignment', 'bottom', 'BackgroundColor', 'none');
text(tNoiseStart, rmsNoise, sprintf('  Noise = %.1f dBFS', noise.rmsLevel), ...
    'color', 'k', 'verticalAlignment', 'top', 'BackgroundColor', 'none');

hold off

xlabel('Time (s)');
ylabel('Power (au)');
xlim([tClip(1) tClip(end)]);

cl = '';
if isfield(detection, 'classification')
    cl = [char(detection.classification) ' — '];
end
snrdB = 10 * log10(rmsSignal / rmsNoise);
if isfield(detection, 't0')
    title(sprintf('%stimeDomain | SNR = %.1f dB | %s', cl, snrdB, datestr(detection.t0)), ...
        'interpreter', 'none');
else
    title(sprintf('%stimeDomain | SNR = %.1f dB', cl, snrdB), 'interpreter', 'none');
end

end
