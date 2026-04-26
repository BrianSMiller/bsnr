function plotTrimDiagnostic(sigAudio, psd, f, t, freqOrig, freqTrimmed, ...
    firstSlice, lastSlice, fMask, firstBin, lastBin, ...
    annot, newT0, newTEnd, sampleRate, nfft, nOverlap, fixedFreq, snrBefore, snrAfter)
% Plot trim diagnostic with energy profiles aligned to spectrogram axes.
%
% Layout:
%   [spectrogram        ] [freq energy (barh) + cumulative on secondary X]
%   [time energy (bar)  ] [text summary                                  ]
%                          + cumulative on secondary Y axis (yyaxis)
%
% Red lines/markers = trimmed bounds. Blue dashed = original bounds.

if nargin < 20, snrAfter  = []; end
if nargin < 19, snrBefore = []; end

fBand   = f(fMask);
psdBand = psd(fMask, :);
psdTrim = psdBand(:, firstSlice:lastSlice);   % time-trimmed for freq profile

sliceEnergy = sum(psdBand, 1);       % full window for time profile
binEnergy   = sum(psdTrim,  2);      % time-trimmed for freq profile
cumT  = min(cumsum(sliceEnergy) / sum(sliceEnergy) * 100, 100);
cumFq = min(cumsum(binEnergy)   / sum(binEnergy)   * 100, 100);

fig = figure('Name', sprintf('trimAnnotation — %s', datestr(annot.t0)), ...
    'Units', 'pixels', 'Position', [50 50 820 520]);

lm = 0.09; bm = 0.11;
sp_w = 0.50; sp_h = 0.60;
fp_w = 0.30; tp_h = 0.22;
gap  = 0.025;

pos1 = [lm,          bm+tp_h+gap, sp_w, sp_h];
pos2 = [lm+sp_w+gap, bm+tp_h+gap, fp_w, sp_h];
pos3 = [lm,          bm,          sp_w, tp_h];
pos4 = [lm+sp_w+gap, bm,          fp_w, tp_h];

fLim = [max(0, freqOrig(1)-30), freqOrig(2)+30];

%% Tile 1: spectrogram
ax1 = axes(fig, 'Position', pos1);
imagesc(ax1, t, f, 10*log10(psd + eps));
set(ax1, 'YDir', 'normal');
colormap(ax1, flipud(gray));
hold(ax1, 'on');
xline(ax1, t(1),          'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
xline(ax1, t(end),        'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
yline(ax1, freqOrig(1),   'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
yline(ax1, freqOrig(2),   'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
xline(ax1, t(firstSlice), 'r-',  'LineWidth', 1.5, 'HandleVisibility', 'off');
xline(ax1, t(lastSlice),  'r-',  'LineWidth', 1.5, 'HandleVisibility', 'off');
if ~fixedFreq && ~isequal(freqOrig, freqTrimmed)
    yline(ax1, freqTrimmed(1), 'r-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    yline(ax1, freqTrimmed(2), 'r-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
end
plot(ax1, NaN, NaN, 'b--', 'LineWidth', 1.2, 'DisplayName', 'Original');
plot(ax1, NaN, NaN, 'r-',  'LineWidth', 1.5, 'DisplayName', 'Trimmed');
hold(ax1, 'off');
ylabel(ax1, 'Frequency (Hz)');
set(ax1, 'XTickLabel', {});
ylim(ax1, fLim);
legend(ax1, 'Location', 'northeast', 'FontSize', 7);
title(ax1, sprintf('Trim diagnostic: %s', datestr(annot.t0)), ...
    'Interpreter', 'none', 'FontSize', 8);

%% Tile 2: freq energy profile — barh on bottom X, cumulative on top X
ax2 = axes(fig, 'Position', pos2);
barh(ax2, fBand, binEnergy, 1, ...
    'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
hold(ax2, 'on');
yline(ax2, freqOrig(1), 'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
yline(ax2, freqOrig(2), 'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
if ~fixedFreq && ~isequal(freqOrig, freqTrimmed)
    yline(ax2, freqTrimmed(1), 'r-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    yline(ax2, freqTrimmed(2), 'r-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
end
hold(ax2, 'off');
xlabel(ax2, 'Energy', 'FontSize', 7);
set(ax2, 'YTickLabel', {});
ylim(ax2, fLim);
% Title inside plot to avoid collision with secondary X axis
text(ax2, 0.97, 0.97, 'Freq profile', 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'FontSize', 7.5, 'Color', [0.3 0.3 0.3]);
grid(ax2, 'on');

% Overlay cumulative on secondary X axis using a twin axes
ax2b = axes(fig, 'Position', pos2);
set(ax2b, 'Color', 'none', 'XAxisLocation', 'top', 'YAxisLocation', 'right');
set(ax2b, 'YTickLabel', {}, 'XLim', [0 100], 'YLim', fLim);
hold(ax2b, 'on');
plot(ax2b, cumFq, fBand, 'k-', 'LineWidth', 1.2);
% Mark trim boundaries on cumulative
pcts = [2.5, 97.5];
for k = 1:2
    idx = find(cumFq >= pcts(k), 1, 'first');
    if ~isempty(idx)
        plot(ax2b, cumFq(idx), fBand(idx), 'ro', ...
            'MarkerSize', 5, 'MarkerFaceColor', 'r');
    end
end
hold(ax2b, 'off');
xlabel(ax2b, 'Cumulative (%)', 'FontSize', 7);
set(ax2b, 'YTickLabel', {}, 'XLim', [0 100]);

%% Tile 3: time energy profile — bar on left Y, cumulative on right Y
ax3 = axes(fig, 'Position', pos3);
yyaxis(ax3, 'left');
bar(ax3, t, sliceEnergy, 1, ...
    'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
ax3.YColor = [0.2 0.5 0.8];
ylabel(ax3, 'Energy', 'FontSize', 7);
hold(ax3, 'on');
xline(ax3, t(1),          'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
xline(ax3, t(end),        'b--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
xline(ax3, t(firstSlice), 'r-',  'LineWidth', 1.5, 'HandleVisibility', 'off');
xline(ax3, t(lastSlice),  'r-',  'LineWidth', 1.5, 'HandleVisibility', 'off');
hold(ax3, 'off');
yyaxis(ax3, 'right');
plot(ax3, t, cumT, 'k-', 'LineWidth', 1.2);
ylim(ax3, [0 100]);
hold(ax3, 'on');
% Mark trim boundaries on cumulative
for k = 1:2
    idx = find(cumT >= pcts(k), 1, 'first');
    if ~isempty(idx)
        plot(ax3, t(idx), cumT(idx), 'ro', ...
            'MarkerSize', 5, 'MarkerFaceColor', 'r');
    end
end
hold(ax3, 'off');
ylabel(ax3, 'Cumulative (%)', 'FontSize', 7);
ax3.YColor = [0 0 0];
xlabel(ax3, 'Time (s)', 'FontSize', 7);
title(ax3, 'Time profile', 'FontSize', 8);
grid(ax3, 'on');

%% Tile 4: text summary
ax4 = axes(fig, 'Position', pos4);
axis(ax4, 'off');
tOrigStart = datestr(annot.t0,  'HH:MM:SS');
tOrigEnd   = datestr(annot.tEnd, 'HH:MM:SS');
tTrimStart = datestr(newT0,      'HH:MM:SS');
tTrimEnd   = datestr(newTEnd,    'HH:MM:SS');
tOrigDur   = t(end) - t(1);
tTrimDur   = t(lastSlice) - t(firstSlice);

% Two-column table: Original | Trimmed
hdr = sprintf('%-12s  %-10s  %-10s', '',           'Original',   'Trimmed');
sep = sprintf('%-12s  %-10s  %-10s', '----------', '----------', '----------');
r1  = sprintf('%-12s  %-10s  %-10s', 'Start',       tOrigStart,   tTrimStart);
r2  = sprintf('%-12s  %-10s  %-10s', 'End',          tOrigEnd,     tTrimEnd);
r3  = sprintf('%-12s  %-10s  %-10s', 'Duration', ...
    sprintf('%.2f s', tOrigDur),  sprintf('%.2f s', tTrimDur));
r4  = sprintf('%-12s  %-10s  %-10s', 'Freq (Hz)', ...
    sprintf('[%.0f  %.0f]', freqOrig(1),    freqOrig(2)), ...
    sprintf('[%.0f  %.0f]', freqTrimmed(1), freqTrimmed(2)));

summaryStr = sprintf('%s\n%s\n%s\n%s\n%s\n%s', hdr, sep, r1, r2, r3, r4);

if ~isempty(snrBefore) && ~isempty(snrAfter)
    r5 = sprintf('%-12s  %-10s  %-10s', 'SNR (dB)', ...
        sprintf('%.1f', snrBefore), sprintf('%.1f', snrAfter));
    summaryStr = sprintf('%s\n%s', summaryStr, r5);
end

text(ax4, 0.95, 0.05, summaryStr, 'Units', 'normalized', ...
    'FontSize', 7.5, 'VerticalAlignment', 'bottom', ...
    'HorizontalAlignment', 'right', 'FontName', 'FixedWidth');

%% Link spectrogram Y to freq profile Y, spectrogram X to time profile X
linkaxes([ax1 ax2 ax2b], 'y');
linkaxes([ax1 ax3], 'x');
% Note: ax3 Y axes intentionally NOT linked to freq axes

drawnow;
end
