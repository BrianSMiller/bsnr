function spectroAnnotationAndNoise( ...
    detection, noise, soundFolder, plotParams, snr, metadata)
% Plot a spectrogram with signal/noise window overlays into the current axes.
%
% Draws into gca — the caller is responsible for creating and positioning
% the axes (e.g. via figure/subplot/nexttile). This keeps figure layout
% decisions out of this function entirely.
%
% INPUTS
%   detection     Scalar annotation struct. Required fields:
%                   .t0, .tEnd     Matlab datenums
%                   .duration      seconds
%                   .freq          [lowHz highHz]
%                   .channel       channel index
%                   .fileInfo      from getAudioFromFiles
%                   .rmsLevel      signal RMS in dBFS (set by snrEstimate)
%                   .classification  (optional) string for title prefix
%
%   noise         Scalar struct, same shape as detection, plus:
%                   .rmsLevel      noise RMS in dBFS (set by snrEstimate)
%
%   soundFolder   wavFolderInfo struct array for the recording folder.
%
%   plotParams Display parameter struct:
%                   .freq        [lowHz highHz] band for colour scaling
%                   .yLims       [minHz maxHz] y-axis limits
%                   .win         FFT window length (samples)
%                   .overlap     FFT overlap (samples)
%                   .pre         pre-clip buffer before noise window (s)
%                   .post        post-clip buffer after detection (s)
%                   .ridgeFreq   (optional) Hz vector, one per signal slice,
%                                drawn as a cyan overlay for ridge method
%
%   snr           SNR in dB, shown as a text annotation.
%
%   metadata      Calibration metadata struct, or [].
%
% TODO(annotation-interface): Replace direct field access on detection and
% noise window placement.
%
% Brian Miller, Australian Antarctic Division, 2017.
% Refactored 2025.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Load clip audio
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sampleRate    = detection.fileInfo(1).sampleRate;
freq          = plotParams.freq;

clip          = detection;
clip.t0       = noise.t0 - plotParams.pre / 86400;
clip.tEnd     = max([detection.tEnd, noise.tEnd]) + plotParams.post / 86400;
clip.duration = (clip.tEnd - clip.t0) * 86400;

clip.audio = getAudioFromFiles(soundFolder, clip.t0, clip.tEnd, ...
    channel=clip.channel, newRate=sampleRate);

if isempty(clip.audio) || clip.duration * sampleRate < plotParams.win
    warning('spectroAnnotationAndNoise:clipTooShort', ...
        'Clip too short for one FFT window — skipping plot.');
    return
end

% Apply click removal to the display clip if requested.
% When snrEstimate threads params.removeClicks through to plotParams,
% the displayed spectrogram uses the same cleaned audio as the SNR computation.
if isfield(plotParams, 'removeClicks') && ~isempty(plotParams.removeClicks)
    rc = plotParams.removeClicks;
    if isstruct(rc)
        rcThresh = rc.threshold;
        rcPower  = rc.power;
    else
        rcThresh = 3;     % legacy boolean true -> use defaults
        rcPower  = 1000;
    end
    if exist('removeClicks', 'file')
        clip.audio = removeClicks(clip.audio, rcThresh, rcPower);
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Time-frequency representation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Use fsst for synchrosqueeze method (sharper TF localisation),
% standard spectrogram for all other methods.
useFsst = isfield(plotParams, 'snrType') && ...
    strcmpi(plotParams.snrType, 'synchrosqueeze');

if useFsst
    win = hann(plotParams.win);
    [sst, f, t] = fsst(clip.audio, sampleRate, win);
    winNorm = sampleRate * sum(win.^2);
    p = abs(sst).^2 / winNorm;
    if ~isempty(metadata)
        p = applyCalibration(p, f, t, metadata);
    end
else
    [~, f, t, p] = spectrogram(clip.audio, ...
        plotParams.win, plotParams.overlap, plotParams.win, ...
        sampleRate, 'yaxis');
    if ~isempty(metadata)
        p = applyCalibration(p, f, t, metadata);
    end
end

% Colour limits derived from out-of-band noise floor.
% Using only frequencies outside the annotation band avoids tonal
% signals skewing the percentiles and compressing the colour scale.
% Upper clim is set well above the noise floor so the signal band
% is clearly visible without saturating the display.
%
% PSD from spectrogram() is in V^2/Hz (uncalibrated) or Pa^2/Hz (calibrated).
% Both are power spectral density — 10*log10 is the correct conversion in
% both cases.  Using 20*log10 would double all values and is appropriate
% only for amplitude spectra, not PSD.
pToDb = @(x) 10 * log10(x);

fIx      = f >= freq(1) & f <= freq(2);            % annotation band (for overlays)
fDispIx  = f >= plotParams.yLims(1) & f <= plotParams.yLims(2);
fNoiseIx = fDispIx & ~fIx;                         % display range minus annotation band
if sum(fNoiseIx) < 3
    fNoiseIx = fDispIx;                            % fallback if band covers most of display
end
pNoisedB    = pToDb(p(fNoiseIx, :));
noiseFloor  = median(pNoisedB(:));
noiseSpread = min(diff(quantile(pNoisedB(:), [0.1 0.9])), 20);   % cap spread at 20 dB
cLim        = [noiseFloor - noiseSpread, noiseFloor + 3*noiseSpread];
cLim(2)     = min(cLim(2), cLim(1) + 60);   % cap total range at 60 dB

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Draw into current axes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

imagesc(t, f, pToDb(p));
set(gca, 'ydir',   'normal');
set(gca, 'clim',   cLim);
set(gca, 'layer',  'top');
colormap(gca, flipud(gray));
cb = colorbar('eastoutside');
if ~isempty(metadata)
    ylabel(cb, 'dB re 1 \muPa^2/Hz');
else
    ylabel(cb, 'dB re 1 V^2/Hz');
end
colorbarFixTickLabel(cb, 'auto');
xlabel('Time (s)');
ylabel('Frequency (Hz)');
ylim(plotParams.yLims);

cl = '';
if isfield(clip, 'classification')
    cl = [char(clip.classification) ' — '];
end
title(sprintf('%s%s', cl, datestr(clip.t0)), 'interpreter', 'none');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Overlays
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

tOffset = @(dn) (dn - clip.t0) * 86400;   % datenum -> seconds from clip start

yLims = ylim;
yMax  = yLims(2);
yMin  = yLims(1);
tSigMid = (tOffset(detection.t0) + tOffset(detection.tEnd)) / 2;

% Unit label depends on whether calibration was applied
levelUnit = 'dBFS';
if ~isempty(metadata), levelUnit = 'dBuPa'; end

if isfield(plotParams, 'quantileThresh') && ~isempty(plotParams.quantileThresh)
    % Quantiles method: no separate noise window, so only the signal window
    % boundary is drawn — as a dark green horizontal line at freq, matching
    % the standard overlay. The 85th/15th percentile contours show where the
    % signal/noise threshold sits within the TF plane.
    tSig0 = tOffset(detection.t0);
    tSig1 = tOffset(detection.tEnd);
    thresh85 = plotParams.quantileThresh;   % linear PSD, 85th percentile
    thresh15 = thresh85 * (0.665214 / 2.897120);   % 15th percentile (exponential theory)
    thresh85dB = pToDb(thresh85);
    thresh15dB = pToDb(thresh15);

    % Signal window boundary — dark green horizontal line, same as standard overlay
    line([tSig0 tSig1], [1 1]' * freq, 'color', [0 0.5 0], 'linewidth', 2);

    % Contour lines at 85th/15th percentile PSD thresholds within the band
    fMask = f >= freq(1) & f <= freq(2);
    if sum(fMask) > 1 && length(t) > 1
        pBanddB   = pToDb(p(fMask, :));
        fBand     = f(fMask);
        holdState = ishold;
        hold on;
        contour(t, fBand, pBanddB, [thresh85dB thresh85dB], ...
            'color', [0 0.5 0], 'linewidth', 1.5);
        contour(t, fBand, pBanddB, [thresh15dB thresh15dB], ...
            'color', [0.5 0 0], 'linewidth', 1.5);
        if ~holdState; hold off; end
    end

else
    % Standard: noise window (dark red) and signal window (dark green) lines.
    % When excludeTimes is present (gap between noise and signal), draw
    % the noise lines only at the actual measured noise bounds.
    hasGap = isfield(plotParams, 'excludeTimes') && ...
             ~isempty(plotParams.excludeTimes);
    if hasGap
        exT = plotParams.excludeTimes;   % [gapStart, gapEnd] in datenums
        line(tOffset([noise.t0, exT(1)]), [1 1]' * freq, ...
            'color', [0.5 0 0], 'linewidth', 2);
        line(tOffset([exT(2), noise.tEnd]), [1 1]' * freq, ...
            'color', [0.5 0 0], 'linewidth', 2);
        line([tOffset(exT(1)) tOffset(exT(1))], freq, ...
            'color', [0.5 0 0], 'linewidth', 1, 'linestyle', ':');
        line([tOffset(exT(2)) tOffset(exT(2))], freq, ...
            'color', [0.5 0 0], 'linewidth', 1, 'linestyle', ':');
    else
        line(tOffset([noise.t0, noise.tEnd]), [1 1]' * freq, ...
            'color', [0.5 0 0], 'linewidth', 2);
    end
    line(tOffset([detection.t0, detection.tEnd]), [1 1]' * freq, ...
        'color', [0 0.5 0], 'linewidth', 2);
end

% --- Two corner labels, combining related info ---

% Top-right: SNR + signal level (green)
if isfield(detection, 'rmsLevel') && isfinite(detection.rmsLevel)
    sigStr = sprintf('SNR = %4.1f dB\nSig = %4.1f %s', snr, detection.rmsLevel, levelUnit);
else
    sigStr = sprintf('SNR = %4.1f dB', snr);
end
text(tOffset(detection.tEnd), yMax, sigStr, ...
    'color', [0 0.5 0], 'FontSize', 7, 'verticalAlignment', 'top', ...
    'horizontalAlignment', 'right', 'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% Bottom-left: noise level + noiseVar (dark red)
noiseVarStr = '';
if isfield(plotParams, 'noiseVar') && ~isempty(plotParams.noiseVar)
    noiseVarStr = sprintf('\nnVar = %.2g', plotParams.noiseVar);
end
if isfield(noise, 'rmsLevel') && isfinite(noise.rmsLevel)
    noiseStr = sprintf('Noise = %4.1f %s%s', noise.rmsLevel, levelUnit, noiseVarStr);
else
    noiseStr = sprintf('Noise%s', noiseVarStr);
end
text(tOffset(noise.t0), yMin, noiseStr, ...
    'color', [0.5 0 0], 'FontSize', 7, 'verticalAlignment', 'bottom', ...
    'horizontalAlignment', 'left', 'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% Ridge overlay (cyan) — only present for snrType='ridge' or 'synchrosqueeze'
if isfield(plotParams, 'ridgeFreq') && ~isempty(plotParams.ridgeFreq)
    nRidge = length(plotParams.ridgeFreq);
    tRidge = linspace(tOffset(detection.t0), tOffset(detection.tEnd), nRidge);
    line(tRidge, plotParams.ridgeFreq(:)', 'color', 'c', 'linewidth', 1.5);
    % Place label just below the annotation band (below freq(1)) so it does
    % not overlap the green/red signal-window boundary lines.
    labelOffset = (freq(2) - freq(1)) * 0.15;   % 15% of band width below band
    text(tOffset(detection.t0), freq(1) - labelOffset, 'Ridge', ...
        'color', 'c', 'FontSize', 7, 'verticalAlignment', 'top', ...
        'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end

% NIST spectrogram contour overlay — only when params.nistDisplay='spectrogram'.
% Draws iso-power contour lines on the spectrogram at the noise-peak and
% signal 95th-percentile PSD thresholds estimated by the NIST algorithm.
% These are the same two levels shown as vertical lines on the histogram,
% but expressed as contours on the time-frequency plane — directly
% analogous to the quantile contours.
if isfield(plotParams, 'nistThresh') && ~isempty(plotParams.nistThresh)
    fMask = f >= freq(1) & f <= freq(2);
    if sum(fMask) > 1 && length(t) > 1
        pBanddB     = pToDb(p(fMask, :));
        fBand       = f(fMask);
        noiseThrdB  = pToDb(plotParams.nistThresh(1));
        signalThrdB = pToDb(plotParams.nistThresh(2));
        holdState   = ishold;
        hold on;
        contour(t, fBand, pBanddB, [noiseThrdB  noiseThrdB],  'color', [0.5 0 0], 'linewidth', 1.5);
        contour(t, fBand, pBanddB, [signalThrdB signalThrdB], 'color', [0 0.5 0], 'linewidth', 1.5);
        if ~holdState; hold off; end
    end
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helper
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function specPsd = applyCalibration(specPsd, sF, sT, metadata)

adVpeakdB       = 10 * log10(1 / metadata.adPeakVolt.^2);
frontEndGain_dB = interp1(log10(metadata.frontEndFreq_Hz), ...
    metadata.frontEndGain_dB, log10(sF), 'linear', 'extrap');
caldB           = metadata.hydroSensitivity_dB + frontEndGain_dB + adVpeakdB;
caldB(isnan(caldB) | isinf(caldB)) = -1000;
specPsd         = specPsd ./ repmat(10.^(caldB/10), 1, size(specPsd, 2));

end
