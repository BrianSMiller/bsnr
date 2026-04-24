function plotBandSamplePower(clipAudio, clipT0, detection, noise, ...
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
    warning('plotBandSamplePower:filterFailed', 'Bandpass filter failed.');
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

levelUnit = 'dBFS';   % plotBandSamplePower has no metadata access; always dBFS
snrDB     = 10 * log10(rmsSignal / rmsNoise);

% Background trace in light grey
plot(tClip, power, 'color', [0.7 0.7 0.7], 'linewidth', 0.5, ...
    'HandleVisibility', 'off');
hold on

% Highlight noise window in dark red
noiseIx = tClip >= tNoiseStart & tClip <= tNoiseEnd & ...
         ~(tClip >= tSigStart  & tClip <= tSigEnd);
plot(tClip(noiseIx), power(noiseIx), 'color', [0.5 0 0], 'linewidth', 1, ...
    'DisplayName', sprintf('Noise (%.1f %s)', 10*log10(rmsNoise), levelUnit));

% Highlight signal window in dark green
sigIx = tClip >= tSigStart & tClip <= tSigEnd;
plot(tClip(sigIx), power(sigIx), 'color', [0 0.5 0], 'linewidth', 1.5, ...
    'DisplayName', sprintf('Signal (%.1f %s)', 10*log10(rmsSignal), levelUnit));

% RMS level lines
plot([tNoiseStart tSigStart],   rmsNoise  * [1 1], 'r', 'linewidth', 2, ...
    'HandleVisibility', 'off');
plot([tSigEnd     tNoiseEnd],   rmsNoise  * [1 1], 'r', 'linewidth', 2, ...
    'HandleVisibility', 'off');
plot([tSigStart   tSigEnd],     rmsSignal * [1 1], 'g', 'linewidth', 2, ...
    'HandleVisibility', 'off');

% One-sided errorbar for noise std dev (power is always positive)
noiseStd = sqrt(noiseVar);
line([tNoiseStart tNoiseStart], [rmsNoise rmsNoise + noiseStd], ...
    'color', 'k', 'linewidth', 2, 'HandleVisibility', 'off');
xLim = xlim;
line([tNoiseStart - diff(xLim)*0.01, tNoiseStart + diff(xLim)*0.01], ...
    [rmsNoise + noiseStd, rmsNoise + noiseStd], 'color', 'k', 'linewidth', 2, ...
    'HandleVisibility', 'off');

% Window boundary markers
yLim = ylim;
line([tSigStart   tSigStart],   yLim, 'color', [0 0.5 0], 'linewidth', 1, ...
    'linestyle', '--', 'HandleVisibility', 'off');
line([tSigEnd     tSigEnd],     yLim, 'color', [0 0.5 0], 'linewidth', 1, ...
    'linestyle', '--', 'HandleVisibility', 'off');
line([tNoiseStart tNoiseStart], yLim, 'color', [0.5 0 0], 'linewidth', 1, ...
    'linestyle', '--', 'HandleVisibility', 'off');
line([tNoiseEnd   tNoiseEnd],   yLim, 'color', [0.5 0 0], 'linewidth', 1, ...
    'linestyle', '--', 'HandleVisibility', 'off');

% SNR label — top left inside axes
yLim = ylim;
text(tClip(1), yLim(2), sprintf('SNR = %.1f dB', snrDB), ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
    'FontSize', 6, ...
    'BackgroundColor', 'none', 'EdgeColor', 'none');

lg = legend('Location', 'northoutside', 'FontSize', 6, 'Box', 'off', ...
    'NumColumns', 2);
lg.ItemTokenSize = [10 6];
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
