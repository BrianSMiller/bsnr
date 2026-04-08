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
    % Clamp freq to valid range — designfilt requires strictly within (0, Nyquist)
    nyquist  = sampleRate / 2;
    freqSafe = [max(freq(1), nyquist * 0.01), min(freq(2), nyquist * 0.99)];
    filterOrder = max(48, round(10 * sampleRate / diff(freqSafe)));
    filterOrder = filterOrder + mod(filterOrder, 2);
    d       = designfilt('bandpassfir', 'FilterOrder', filterOrder, ...
        'CutoffFrequency1', freqSafe(1), 'CutoffFrequency2', freqSafe(2), ...
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

% Text labels — font and colour matching spectroAnnotationAndNoise conventions.
% Signal: centred horizontally in the signal window, near the top.
% Noise: right-aligned at the right edge of the noise region, near the bottom.
yLim     = ylim;
yMax     = yLim(2);
yMin     = yLim(1);
tSigMid  = (tSigStart + tSigEnd) / 2;
tNoiseR  = max(tNoiseStart, tSigStart - 0.01*(tClip(end)-tClip(1)));   % rightmost noise edge

levelUnit = 'dBFS';   % plotTimeDomainPower has no metadata access; always dBFS

if isfield(detection, 'rmsLevel') && isfinite(detection.rmsLevel)
    sigStr = sprintf('SNR = %4.1f dB\nSig = %4.1f %s', ...
        10*log10(rmsSignal/rmsNoise), detection.rmsLevel, levelUnit);
else
    sigStr = sprintf('SNR = %4.1f dB', 10*log10(rmsSignal/rmsNoise));
end
text(tSigMid, yMax, sigStr, ...
    'color', [0 0.5 0], 'FontSize', 7, 'verticalAlignment', 'top', ...
    'horizontalAlignment', 'center', 'BackgroundColor', 'w', ...
    'EdgeColor', 'none', 'Margin', 1);

if isfield(noise, 'rmsLevel') && isfinite(noise.rmsLevel)
    noiseStr = sprintf('Noise = %4.1f %s', noise.rmsLevel, levelUnit);
else
    noiseStr = 'Noise';
end
text(tNoiseEnd, yMin, noiseStr, ...
    'color', [0.5 0 0], 'FontSize', 7, 'verticalAlignment', 'bottom', ...
    'horizontalAlignment', 'right', 'BackgroundColor', 'w', ...
    'EdgeColor', 'none', 'Margin', 1);

hold off

xlabel('Time (s)', 'FontSize', 7);
ylabel('Power (au)', 'FontSize', 7);
xlim([tClip(1) tClip(end)]);

if isfield(detection, 'classification')
    titleStr = sprintf('%s — timeDomain', char(detection.classification));
else
    titleStr = 'timeDomain';
end
title(titleStr, 'interpreter', 'none', 'FontSize', 7);

end
