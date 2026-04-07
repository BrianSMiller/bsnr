function spectroAnnotationAndNoise( ...
    detection, noise, soundFolder, spectroParams, snr, metadata)
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
%   spectroParams Display parameter struct:
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
% noise with standardised accessor calls once that refactor is complete.
%
% Brian Miller, Australian Antarctic Division, 2017.
% Refactored 2025.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Load clip audio
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sampleRate    = detection.fileInfo(1).sampleRate;
freq          = spectroParams.freq;

clip          = detection;
clip.t0       = noise.t0 - spectroParams.pre / 86400;
clip.tEnd     = max([detection.tEnd, noise.tEnd]) + spectroParams.post / 86400;
clip.duration = (clip.tEnd - clip.t0) * 86400;

clip.audio = getAudioFromFiles(soundFolder, clip.t0, clip.tEnd, ...
    channel=clip.channel, newRate=sampleRate);

if isempty(clip.audio) || clip.duration * sampleRate < spectroParams.win
    warning('spectroAnnotationAndNoise:clipTooShort', ...
        'Clip too short for one FFT window — skipping plot.');
    return
end

% removeClicks is an optional dependency from longTermRecorders.
% Disabled by default — the threshold (3x wideband RMS) suppresses out-of-band
% energy in wideband noise, making spectrograms appear bandpass-filtered.
% Enable via spectroParams.removeClicks = true for real recordings with clicks.
if isfield(spectroParams, 'removeClicks') && spectroParams.removeClicks ...
        && exist('removeClicks', 'file')
    clip.audio = removeClicks(clip.audio, 3, 1000);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Time-frequency representation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Use fsst for synchrosqueeze method (sharper TF localisation),
% standard spectrogram for all other methods.
useFsst = isfield(spectroParams, 'snrType') && ...
    strcmpi(spectroParams.snrType, 'synchrosqueeze');

if useFsst
    win = hann(spectroParams.win);
    [sst, f, t] = fsst(clip.audio, sampleRate, win);
    winNorm = sampleRate * sum(win.^2);
    p = abs(sst).^2 / winNorm;
    if ~isempty(metadata)
        p = applyCalibration(p, f, t, metadata);
    end
else
    [~, f, t, p] = spectrogram(clip.audio, ...
        spectroParams.win, spectroParams.overlap, spectroParams.win, ...
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
fIx      = f >= freq(1) & f <= freq(2);            % annotation band (for overlays)
fDispIx  = f >= spectroParams.yLims(1) & f <= spectroParams.yLims(2);
fNoiseIx = fDispIx & ~fIx;                         % display range minus annotation band
if sum(fNoiseIx) < 3
    fNoiseIx = fDispIx;                            % fallback if band covers most of display
end
pNoisedB    = 20 * log10(p(fNoiseIx, :));
noiseFloor  = median(pNoisedB(:));
noiseSpread = min(diff(quantile(pNoisedB(:), [0.1 0.9])), 20);   % cap spread at 20 dB
cLim        = [noiseFloor - noiseSpread, noiseFloor + 3*noiseSpread];
cLim(2)     = min(cLim(2), cLim(1) + 60);   % cap total range at 60 dB

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Draw into current axes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

imagesc(t, f, 20 * log10(p));
set(gca, 'ydir',   'normal');
set(gca, 'clim',   cLim);
set(gca, 'xtick',  0 : floor(clip.duration));
set(gca, 'layer',  'top');
colormap(gca, flipud(gray));
cb = colorbar('eastoutside');
if ~isempty(metadata)
    ylabel(cb, 'dB re 1 \muPa^2/Hz');
else
    ylabel(cb, 'dBFS');
end
xlabel('Time (s)');
ylabel('Frequency (Hz)');
ylim(spectroParams.yLims);

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

if isfield(spectroParams, 'quantileThresh') && ~isempty(spectroParams.quantileThresh)
    % Quantiles method: show full clip spectrogram (same as other methods)
    % with cyan dashed lines marking the annotation bounds, and horizontal
    % contour lines at the 85th/15th percentile PSD thresholds within the band.
    tSig0 = tOffset(detection.t0);
    tSig1 = tOffset(detection.tEnd);
    thresh85 = spectroParams.quantileThresh;   % linear PSD, 85th percentile
    thresh15 = thresh85 * (0.665214 / 2.897120);   % 15th percentile (exponential theory)
    thresh85dB = 20 * log10(thresh85);
    thresh15dB = 20 * log10(thresh15);

    % Annotation bounds — cyan dashed vertical lines full height
    line([tSig0 tSig0], [yMin yMax], 'color', 'c', 'linewidth', 1.5, 'linestyle', '--');
    line([tSig1 tSig1], [yMin yMax], 'color', 'c', 'linewidth', 1.5, 'linestyle', '--');

    % Contour lines: use the full p matrix but restrict frequency to band
    fMask = f >= freq(1) & f <= freq(2);
    if sum(fMask) > 1 && length(t) > 1
        pBanddB   = 20 * log10(p(fMask, :));
        fBand     = f(fMask);
        holdState = ishold;
        hold on;
        contour(t, fBand, pBanddB, [thresh85dB thresh85dB], ...
            'color', [0 0.5 0], 'linewidth', 1.5);
        contour(t, fBand, pBanddB, [thresh15dB thresh15dB], ...
            'color', [0.5 0 0], 'linewidth', 1.5);
        if ~holdState; hold off; end
    end

    % Quantiles: p=0.85/0.15 labels at top-left of signal region
    % SNR combined with signal level at top-right (yMax)
    text(tSig0, yMax, sprintf('SNR = %.1f dB\np=0.85/0.15', snr), ...
        'color', 'g', 'verticalAlignment', 'top', 'FontSize', 7, ...
        'horizontalAlignment', 'left', 'BackgroundColor', 'w', 'EdgeColor', 'none', ...
        'Margin', 1);
else
    % Standard: noise window (dark red) and signal window (dark green) lines.
    % When excludeTimes is present (gap between noise and signal), draw
    % the noise lines only at the actual measured noise bounds.
    hasGap = isfield(spectroParams, 'excludeTimes') && ...
             ~isempty(spectroParams.excludeTimes);
    if hasGap
        exT = spectroParams.excludeTimes;   % [gapStart, gapEnd] in datenums
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
if isfield(spectroParams, 'noiseVar') && ~isempty(spectroParams.noiseVar)
    noiseVarStr = sprintf('\nnVar = %.2g', spectroParams.noiseVar);
end
if isfield(noise, 'rmsLevel') && isfinite(noise.rmsLevel)
    noiseStr = sprintf('Noise = %4.1f %s%s', noise.rmsLevel, levelUnit, noiseVarStr);
else
    noiseStr = sprintf('Noise%s', noiseVarStr);
end
text(tOffset(noise.t0), yMin, noiseStr, ...
    'color', [0.5 0 0], 'FontSize', 7, 'verticalAlignment', 'bottom', ...
    'horizontalAlignment', 'left', 'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);

% Ridge overlay (cyan) — only present for snrType='ridge'
if isfield(spectroParams, 'ridgeFreq') && ~isempty(spectroParams.ridgeFreq)
    nRidge = length(spectroParams.ridgeFreq);
    tRidge = linspace(tOffset(detection.t0), tOffset(detection.tEnd), nRidge);
    line(tRidge, spectroParams.ridgeFreq(:)', 'color', 'c', 'linewidth', 1.5);
    text(tOffset(detection.t0), freq(1), 'Ridge', ...
        'color', 'c', 'FontSize', 7, 'verticalAlignment', 'bottom', ...
        'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
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
