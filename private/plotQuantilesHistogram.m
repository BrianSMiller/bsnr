function plotQuantilesHistogram(psdCells, q85thresh, snr, signalRMSdB, noiseRMSdB, levelUnit)
% Plot the quantiles TF-cell PSD distribution with noise and signal levels marked.
%
% Draws into the current axes (gca). The histogram shows the distribution of
% all in-band spectrogram cell PSD values within the signal window. The
% layout directly mirrors the NIST quick-method histogram:
%
%   Dark red line  — 15th percentile (noise level estimate)
%   Green line     — 85th percentile (signal level estimate, = q85thresh)
%   Bracket        — SNR = gap between the two markers
%
% The 15th/85th split mirrors the NIST quick method (Appendix 1 of stnr.txt),
% applied to spectogram TF cells instead of time-domain 20 ms frames.
% The x-axis is in physical power dB (dBFS or dB re 1 µPa^2/Hz).
%
% INPUTS
%   psdCells     Column vector of all in-band PSD cell values (linear, V^2/Hz)
%   q85thresh    85th percentile threshold (linear, same units as psdCells)
%   snr          SNR in dB
%   signalRMSdB  Signal level in dBFS (or calibrated)
%   noiseRMSdB   Noise level in same units
%   levelUnit    String, e.g. 'dBFS' or 'dB re 1µPa'

if nargin < 6 || isempty(levelUnit)
    levelUnit = 'dBFS';
end

% Convert linear PSD cells to dB
psdCellsdB = 10 * log10(max(psdCells, eps));

% Compute percentile markers
q15thresh    = quantile(psdCells, 0.15);
q15dB        = 10 * log10(max(q15thresh, eps));
q85dB        = 10 * log10(max(q85thresh, eps));

% Build histogram (50 bins across the 1st–99th percentile range)
xLo = quantile(psdCellsdB, 0.01);
xHi = quantile(psdCellsdB, 0.99);
nBins    = 50;
binEdges = linspace(xLo, xHi, nBins + 1);
binCentres = (binEdges(1:end-1) + binEdges(2:end)) / 2;
counts   = histcounts(psdCellsdB, binEdges);
hs       = counts / sum(counts);   % normalise to density

yMax = max(hs) * 1.25;
if yMax == 0, yMax = 1; end
yLim = [0 yMax];

% Add 5% margin on x-axis
margin = (xHi - xLo) * 0.05;
xLo = xLo - margin;
xHi = xHi + margin;

ax = gca;
cla(ax);
hold(ax, 'on');

% Histogram fill and stairs
area(ax, binCentres, hs, 'FaceColor', [0.85 0.85 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
stairs(ax, binCentres, hs, 'Color', [0.5 0.5 0.5], 'LineWidth', 1);

% Noise region shading (below 15th percentile)
patch(ax, [xLo xLo q15dB q15dB], [0 yMax yMax 0], ...
    [0.5 0 0], 'FaceAlpha', 0.10, 'EdgeColor', 'none');

% 15th percentile line + label (noise)
line(ax, [q15dB q15dB], yLim, 'Color', [0.5 0 0], 'LineWidth', 1.5);
text(ax, q15dB, yMax * 0.97, 'Noise (p=0.15)', ...
    'Color', [0.5 0 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% 85th percentile line + label (signal)
line(ax, [q85dB q85dB], yLim, 'Color', [0 0.5 0], 'LineWidth', 1.5);
text(ax, q85dB, yMax * 0.97, 'Signal (p=0.85)', ...
    'Color', [0 0.5 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% SNR bracket
bracketY = yMax * 0.60;
tickH    = yMax * 0.04;
line(ax, [q15dB q85dB], [bracketY bracketY], 'Color', 'k', 'LineWidth', 1);
line(ax, [q15dB q15dB], bracketY + [-tickH tickH], 'Color', 'k', 'LineWidth', 1);
line(ax, [q85dB q85dB], bracketY + [-tickH tickH], 'Color', 'k', 'LineWidth', 1);
text(ax, mean([q15dB q85dB]), bracketY + tickH * 1.5, ...
    sprintf('SNR = %.1f dB', snr), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontSize', 7, 'FontWeight', 'bold', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% Signal and noise levels in physical units (bottom right)
text(ax, xHi, yMax * 0.40, ...
    sprintf('Sig   = %.1f %s\nNoise = %.1f %s', ...
        signalRMSdB, levelUnit, noiseRMSdB, levelUnit), ...
    'Color', [0.2 0.2 0.2], 'FontSize', 6, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

set(ax, 'XLim', [xLo xHi], 'YLim', yLim);
xlabel(ax, sprintf('Cell PSD (%s/Hz)', levelUnit), 'FontSize', 7);
ylabel(ax, 'Relative frequency', 'FontSize', 7);
title(ax, 'quantiles — TF cell PSD distribution', 'FontSize', 7);
hold(ax, 'off');

end
