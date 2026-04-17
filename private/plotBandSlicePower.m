function plotBandSlicePower(sigSlicePowers, noiseSlicePowers, annot, noise, snr, levelUnit)
% Plot per-STFT-slice band power vs time for signal and noise windows.
%
% Shows the time series of per-slice band power estimates that underlie the
% SNR calculation for spectrogram-based methods.  Green = signal window,
% red = noise window.  Horizontal lines at the respective means.
%
% This is the unified time-series display for all STFT-based methods
% (spectrogram, spectrogramSlices, ridge, synchrosqueeze, quantiles, nist).
% For the timeDomain method, use plotBandSamplePower instead, which shows
% instantaneous per-sample power of the FIR-filtered waveform.
%
% INPUTS
%   sigSlicePowers    Per-slice band power, signal window (linear, column vector)
%   noiseSlicePowers  Per-slice band power, noise window (linear, column vector)
%   annot             Annotation struct with .t0, .tEnd, .duration
%   noise             Noise window struct with .t0, .tEnd
%   snr               SNR in dB
%   levelUnit         String label for y-axis, e.g. 'dBFS' or 'dB re 1 µPa'

if nargin < 6 || isempty(levelUnit)
    levelUnit = 'dBFS';
end

% Convert to dB
sigDB   = 10 * log10(max(sigSlicePowers(:),   eps));
noiseDB = 10 * log10(max(noiseSlicePowers(:), eps));
sMeandB = mean(sigDB);
nMeandB = mean(noiseDB);

% Build time axes — slice index mapped to seconds from start of noise window
tNoise = linspace(0, noise.tEnd - noise.t0, numel(noiseDB)) * 86400;
% Signal starts after noise window gap; approximate offset
sigOffset = (annot.t0 - noise.t0) * 86400;
tSig   = sigOffset + linspace(0, annot.duration, numel(sigDB));

ax = gca;
cla(ax);
hold(ax, 'on');

% Noise slices — red
plot(ax, tNoise, noiseDB, 'Color', [0.7 0.1 0.1], 'LineWidth', 0.8, ...
    'DisplayName', sprintf('Noise (%.1f %s)', nMeandB, levelUnit));
line(ax, [tNoise(1) tNoise(end)], [nMeandB nMeandB], ...
    'Color', [0.5 0 0], 'LineWidth', 1.5, 'LineStyle', '--', ...
    'HandleVisibility', 'off');

% Signal slices — green
plot(ax, tSig, sigDB, 'Color', [0.1 0.6 0.1], 'LineWidth', 0.8, ...
    'DisplayName', sprintf('Signal (%.1f %s)', sMeandB, levelUnit));
line(ax, [tSig(1) tSig(end)], [sMeandB sMeandB], ...
    'Color', [0 0.45 0], 'LineWidth', 1.5, 'LineStyle', '--', ...
    'HandleVisibility', 'off');

% Vertical boundary between noise and signal windows
xBound = sigOffset;
yL = [min([sigDB; noiseDB]) - 1, max([sigDB; noiseDB]) + 1];
line(ax, [xBound xBound], yL, 'Color', [0.5 0.5 0.5], ...
    'LineWidth', 1, 'LineStyle', ':', 'HandleVisibility', 'off');

% SNR label — top left inside axes
text(ax, tNoise(1), yL(2), sprintf('SNR = %.1f dB', snr), ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
    'FontSize', 6, ...
    'BackgroundColor', 'none', 'EdgeColor', 'none');

set(ax, 'YLim', yL);
xlabel(ax, 'Time (s)', 'FontSize', 7);
ylabel(ax, sprintf('Band power (%s)', levelUnit), 'FontSize', 7);
title(ax, 'Per-slice band power', 'FontSize', 7);
lg = legend(ax, 'Location', 'northoutside', 'FontSize', 6, 'Box', 'off', ...
    'NumColumns', 2);
lg.ItemTokenSize = [10 6];
hold(ax, 'off');

end
