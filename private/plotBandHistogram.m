function plotBandHistogram(sigSlicePowers, noiseSlicePowers, snr, ...
    rmsSignal, rmsNoise, noiseVar, levelUnit, useLurton)
% Plot overlaid per-slice band power distributions for signal and noise.
%
% Red histogram   — noise window per-slice band powers
% Green histogram — signal window per-slice band powers
% Dark red vertical line   — noise mean (N)
% Dark green vertical line — signal mean (S)
% Horizontal error bar     — noise mean ± 1 std (shows noiseVar spread)
% Bracket                  — SNR between N and S
%
% This is the unified histogram display for all methods that produce
% per-slice signal and noise power estimates.  For the NIST method, use
% plotHistogramSNR instead (which shows the NIST frame-energy histogram).
% For quantiles, use plotQuantilesHistogram (which shows TF cell PSD
% distributions).
%
% INPUTS
%   sigSlicePowers    Per-slice band power, signal window (linear)
%   noiseSlicePowers  Per-slice band power, noise window (linear)
%   snr               SNR in dB
%   rmsSignal         Mean signal band power (linear)
%   rmsNoise          Mean noise band power (linear)
%   noiseVar          Variance of noise band power (linear)
%   levelUnit         String, e.g. 'dBFS' or 'dB re 1 µPa'
%   useLurton         Logical; if true, label bracket as Lurton SNR

if nargin < 7 || isempty(levelUnit), levelUnit = 'dBFS'; end
if nargin < 8 || isempty(useLurton), useLurton = false;  end

sigDB   = 10 * log10(max(sigSlicePowers(:),   eps));
noiseDB = 10 * log10(max(noiseSlicePowers(:), eps));
nMeandB = mean(noiseDB);   % consistent with histogram x-axis
sMeandB = mean(sigDB);

% Noise std in dB domain — matches what is visible in the histogram
noiseStdDB = std(noiseDB);

% Shared x-axis covering both distributions
allDB  = [sigDB; noiseDB];
xLo    = min(quantile(allDB, 0.01) - 1, nMeandB - 2*noiseStdDB - 1);
xHi    = max(quantile(allDB, 0.99) + 1, sMeandB + 2);
nBins  = 30;
edges      = linspace(xLo, xHi, nBins + 1);
centres    = (edges(1:end-1) + edges(2:end)) / 2;
noiseH     = histcounts(noiseDB, edges) / numel(noiseDB);
signalH    = histcounts(sigDB,   edges) / numel(sigDB);

yMax = max(max(noiseH), max(signalH)) * 1.45;
if yMax == 0, yMax = 1; end

ax = gca;
cla(ax);
hold(ax, 'on');

% Histograms — extend to zero at both ends to avoid truncated appearance
cExt = [edges(1), centres, edges(end)];
noiseHx  = [0, noiseH,  0];
signalHx = [0, signalH, 0];
area(ax, cExt, noiseHx,  'FaceColor', [0.5 0 0], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
stairs(ax, cExt, noiseHx,  'Color', [0.5 0 0], 'LineWidth', 1);
area(ax, cExt, signalHx, 'FaceColor', [0 0.5 0], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
stairs(ax, cExt, signalHx, 'Color', [0 0.5 0], 'LineWidth', 1);

yLim = [0 yMax];

% Noise mean vertical line
line(ax, [nMeandB nMeandB], yLim, 'Color', [0.5 0 0], 'LineWidth', 1.5);
nLabelY = yMax * 0.92;
sLabelY = yMax * 0.92;
if abs(sMeandB - nMeandB) < (xHi - xLo) * 0.12
    sLabelY = yMax * 0.78;
end
text(ax, nMeandB, nLabelY, sprintf('N=%.1f', nMeandB), ...
    'Color', [0.5 0 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'none', 'EdgeColor', 'none');

% Signal mean vertical line
line(ax, [sMeandB sMeandB], yLim, 'Color', [0 0.5 0], 'LineWidth', 1.5);
text(ax, sMeandB, sLabelY, sprintf('S=%.1f', sMeandB), ...
    'Color', [0 0.5 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'none', 'EdgeColor', 'none');

% Noise ± 1 std error bar — positioned above histograms on the noise line
errY  = yMax * 0.75;
tickH = yMax * 0.03;
errLo = nMeandB - noiseStdDB;
errHi = nMeandB + noiseStdDB;
line(ax, [errLo errHi], [errY errY],           'Color', [0.5 0 0], 'LineWidth', 1.5);
line(ax, [errLo errLo], errY + [-tickH tickH], 'Color', [0.5 0 0], 'LineWidth', 1.5);
line(ax, [errHi errHi], errY + [-tickH tickH], 'Color', [0.5 0 0], 'LineWidth', 1.5);
text(ax, errHi, errY, sprintf(' %s=%.1f', char(963), noiseStdDB), ...
    'Color', [0.5 0 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', 'none', 'EdgeColor', 'none');

% SNR bracket
bracketY = yMax * 0.50;
tickHb   = yMax * 0.03;
line(ax, [nMeandB sMeandB], [bracketY bracketY], 'Color', 'k', 'LineWidth', 1);
line(ax, [nMeandB nMeandB], bracketY + [-tickHb tickHb], 'Color', 'k', 'LineWidth', 1);
line(ax, [sMeandB sMeandB], bracketY + [-tickHb tickHb], 'Color', 'k', 'LineWidth', 1);
if useLurton
    snrLabel = sprintf('SNR_{Lurton} = %.1f dB', snr);
else
    snrLabel = sprintf('SNR = %.1f dB', snr);
end
text(ax, mean([nMeandB sMeandB]), yMax * 0.99, snrLabel, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
    'FontSize', 7, 'FontWeight', 'bold', ...
    'BackgroundColor', 'none', 'EdgeColor', 'none');

set(ax, 'XLim', [xLo xHi], 'YLim', yLim);
xlabel(ax, sprintf('Per-slice band power (%s)', levelUnit), 'FontSize', 7);
ylabel(ax, 'Relative frequency', 'FontSize', 7);
title(ax, 'Slice power distributions', 'FontSize', 7);
hold(ax, 'off');

end
