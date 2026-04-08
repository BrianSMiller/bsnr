function plotHistogramSNR(histogramData, snr, signalRMSdB, noiseRMSdB, levelUnit)
% Plot the NIST frame-energy histogram with noise and signal levels marked.
%
% Draws into the current axes (gca). The histogram shows the distribution
% of frame energies across the combined noise+signal window. Two populations
% are visible when SNR is high: a left (noise) peak and a right (signal)
% shoulder or peak. The NIST algorithm estimates noise from the left peak
% and signal from the 95th percentile.
%
% The x-axis is displayed in physical power dB units (dBFS uncalibrated,
% or dB re 1 µPa if calibrated) by shifting the NIST internal scale so
% that the noise peak lands exactly at noiseRMSdB. The SNR gap between
% the two markers is unaffected by this shift.
%
%   Dark red line  — noise peak (modal noise frame energy)
%   Dark red shade — ± half-width of noise peak
%   Green line     — signal level (95th percentile of frame energies)
%   Bracket        — SNR = gap between noise peak and signal level
%
% INPUTS
%   histogramData     Struct from snrHistogram:
%                  .binCentres    bin centres (dB, NIST internal scale)
%                  .histSmooth    smoothed histogram counts
%                  .noisedB       noise peak (dB, NIST internal scale)
%                  .signaldB      signal 95th-percentile (dB, NIST internal scale)
%                  .noiseWidth_dB half-width of noise peak (dB)
%   snr          SNR in dB
%   signalRMSdB  Signal RMS power in dBFS (or dB re 1 µPa if calibrated)
%   noiseRMSdB   Noise RMS power in same units
%   levelUnit    Unit string, e.g. 'dBFS' or 'dB re 1µPa' (optional)

if nargin < 5 || isempty(levelUnit)
    levelUnit = 'dBFS';
end

% Convert NIST internal dB scale to physical power dB units.
% The histogram is stored in 10*log10(Pfull) where Pfull = sum of two
% half-window mean((x*16384)^2). The linear outputs rmsSignal/rmsNoise
% are derived from the same scale, so noiseRMSdB = 10*log10(rmsNoise)
% is offset from histogramData.noisedB by a fixed constant (84.29 dB).
% Applying shift = noiseRMSdB - noisedB to all bin centres maps the
% entire x-axis to physical power dB (dBFS or dB re 1 µPa if calibrated),
% with the noise peak landing exactly at noiseRMSdB.
shift = noiseRMSdB - histogramData.noisedB;

bc  = histogramData.binCentres + shift;
hs  = histogramData.histSmooth / sum(histogramData.histSmooth);  % normalise to density
ndb = histogramData.noisedB  + shift;   % = noiseRMSdB
sdb = histogramData.signaldB + shift;
nw  = histogramData.noiseWidth_dB;      % width is unchanged by a rigid shift

yMax = max(hs) * 1.25;
yLim = [0 yMax];

% Trim x-axis to the 1st–99th percentile of the frame energy distribution.
% The full 500-bin NIST range spans ~125 dB; most of it is empty for any
% real recording. Using the cumulative histogram avoids hard-coding limits
% while still showing the full interesting range around the noise and signal
% peaks with a small margin.
cumHs  = cumsum(hs) / sum(hs);
xLoIdx = find(cumHs >= 0.01, 1, 'first');
xHiIdx = find(cumHs >= 0.99, 1, 'first');
if isempty(xLoIdx), xLoIdx = 1; end
if isempty(xHiIdx), xHiIdx = numel(bc); end
margin = (bc(xHiIdx) - bc(xLoIdx)) * 0.05;   % 5% padding on each side
xLo = bc(xLoIdx) - margin;
xHi = bc(xHiIdx) + margin;

ax = gca;
cla(ax);
hold(ax, 'on');

% Histogram as a step plot (cleaner than fill for a pdf-style view)
stairs(ax, bc, hs, 'Color', [0.5 0.5 0.5], 'LineWidth', 1);
area(ax, bc, hs, 'FaceColor', [0.85 0.85 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.6);

% Noise peak half-width shading
patch(ax, [ndb-nw  ndb-nw  ndb+nw  ndb+nw], [0 yMax yMax 0], ...
    [0.5 0 0], 'FaceAlpha', 0.10, 'EdgeColor', 'none');

% Noise peak line + label
line(ax, [ndb ndb], yLim, 'Color', [0.5 0 0], 'LineWidth', 1.5);
text(ax, ndb, yMax * 0.97, 'Noise', ...
    'Color', [0.5 0 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% Signal level line + label
line(ax, [sdb sdb], yLim, 'Color', [0 0.5 0], 'LineWidth', 1.5);
text(ax, sdb, yMax * 0.97, 'Signal', ...
    'Color', [0 0.5 0], 'FontSize', 6, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% SNR bracket: horizontal line with tick marks at each end + central label
bracketY  = yMax * 0.60;
tickH     = yMax * 0.04;
line(ax, [ndb sdb], [bracketY bracketY], 'Color', 'k', 'LineWidth', 1);
line(ax, [ndb ndb], bracketY + [-tickH tickH], 'Color', 'k', 'LineWidth', 1);
line(ax, [sdb sdb], bracketY + [-tickH tickH], 'Color', 'k', 'LineWidth', 1);
text(ax, mean([ndb sdb]), bracketY + tickH * 1.5, ...
    sprintf('SNR = %.1f dB', snr), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontSize', 7, 'FontWeight', 'bold', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% Bottom-right: signal and noise levels in physical units
text(ax, xHi, yMax * 0.40, ...
    sprintf('Sig   = %.1f %s\nNoise = %.1f %s', ...
        signalRMSdB, levelUnit, noiseRMSdB, levelUnit), ...
    'Color', [0.2 0.2 0.2], 'FontSize', 6, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

set(ax, 'XLim', [xLo xHi], 'YLim', yLim);
xlabel(ax, sprintf('Frame energy (%s)', levelUnit), 'FontSize', 7);
ylabel(ax, 'Relative frequency', 'FontSize', 7);
hold(ax, 'off');

end
