%% bsnr Gallery
% Illustrated examples of bsnr SNR estimation on Antarctic baleen whale
% calls from the IWC-SORP Annotated Library (Miller et al. 2021).
%
% Each section demonstrates one feature of the toolbox. Run the full
% script with |publish| to produce a PDF reference document:
%
%   cd C:\analysis\bsnr\examples
%   publish('bsnr_gallery.m', 'format','pdf', 'outputDir','.\')
%
% *Audio clips* (CC-BY 4.0): Miller et al. (2021)
% doi:10.1038/s41598-020-78995-8 / doi:10.26179/5e6056035c01b
%
% Run |prepareGalleryAudio.m| first if you have the annotated library
% locally; otherwise place pre-extracted clips in |examples/audio/|.

close all;
fprintf('\n=== bsnr gallery ===\n\n');

galleryDir = fileparts(mfilename('fullpath'));
audioDir   = fullfile(galleryDir, 'audio');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Call types and shared setup
% Six call types are used throughout: four Antarctic blue whale (ABW) unit
% types and two fin whale (_Balaenoptera physalus_) call types.
% Parameters are taken from makeSpectrograms.m (Miller 2021 fig. plots).
%
%   ABW Z-call  -- long downswept tonal, 17-28 Hz, ~21 s
%   ABW D-call  -- short broadband downsweep, 44-72 Hz, ~4 s
%   ABW Unit A  -- narrow tonal, 24-28 Hz, ~10 s
%   ABW Unit B  -- narrow tonal, 20-28 Hz, ~12 s
%   Fin 40 Hz   -- short pulse, 32-61 Hz, ~2 s
%   Fin 20 Hz   -- infrasonic pulse, 14-25 Hz, ~2 s
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% label | subdir | t0InClip_s | duration_s | freq_Hz | spectroType
callTypes = {
  'ABW Z'    'abw_z'  10  21  [17  28]  'blue'
  'ABW D'    'abw_d'  10   4  [44  72]  'd'
  'ABW A'    'abw_a'  10  10  [24  28]  'blue'
  'ABW B'    'abw_b'  10  12  [20  28]  'blue'
  'Fin 40Hz' 'bp_40'  10   2  [32  61]  'd'
  'Fin 20Hz' 'bp_20'  10   2  [14  25]  'blue'
};
nTypes = size(callTypes, 1);

methodNames = {'spectrogram','spectrogramSlices','timeDomain', ...
               'ridge','synchrosqueeze','quantiles','nist'};
nMethods = numel(methodNames);
snrTable = nan(nMethods, nTypes);

% Build annotation and spectro-param structs; skip unavailable call types.
annots    = cell(nTypes, 1);
spectroP  = cell(nTypes, 1);
available = false(nTypes, 1);

for ct = 1:nTypes
    wavDir = fullfile(audioDir, callTypes{ct,2});
    if ~exist(wavDir, 'dir')
        fprintf('  [SKIP] %s -- audio not found. Run prepareGalleryAudio.m first.\n', ...
            callTypes{ct,1});
        continue;
    end
    sf = wavFolderInfo(wavDir);
    a.soundFolder    = wavDir;
    a.t0             = sf(1).startDate + callTypes{ct,3} / 86400;
    a.tEnd           = a.t0 + callTypes{ct,4} / 86400;
    a.duration       = callTypes{ct,4};
    a.freq           = callTypes{ct,5};
    a.channel        = 1;
    a.classification = callTypes{ct,1};
    annots{ct}    = a;
    spectroP{ct}  = gallerySpectroParams(callTypes{ct,6}, callTypes{ct,5});
    available(ct) = true;
end

if ~any(available)
    fprintf('No audio available. Run prepareGalleryAudio.m first.\n');
    return;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1. Spectrogram method
% The default method. Mean band power spectral density (PSD) in the
% annotation frequency band from a multi-taper STFT. Signal power is the
% mean PSD of the signal window; noise power is the mean PSD of an
% equal-duration window adjacent to the detection (0.5 s gap each side).
%
%   SNR = 10*log10(rmsSignal / rmsNoise)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 1. spectrogram ---\n');
[~, tlo] = galleryFig('1. Spectrogram method', nTypes, 1);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('spectrogram', spectroP{ct});
    snrTable(1,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 2. Spectrogram slices method
% A more robust variant: takes the *median* band power across STFT time
% slices rather than the mean, reducing sensitivity to transient noise
% bursts or brief signal dropouts within the annotation window.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 2. spectrogramSlices ---\n');
[~, tlo] = galleryFig('2. Spectrogram slices method', nTypes, 2);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('spectrogramSlices', spectroP{ct});
    snrTable(2,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 3. Time-domain method
% Applies a bandpass FIR filter to the annotation band and computes mean
% instantaneous power of the filtered waveform. Uses a high-order FIR
% (order proportional to sampleRate/BW) for strong out-of-band rejection.
% Most appropriate for narrow-band tonal calls.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 3. timeDomain ---\n');
[~, tlo] = galleryFig('3. Time-domain method', nTypes, 3);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('timeDomain', spectroP{ct});
    snrTable(3,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 4. Ridge method
% Tracks the dominant instantaneous frequency ridge using |tfridge|
% (Signal Processing Toolbox). Signal power is the single FFT bin on the
% ridge at each time step; noise is the mean of all other in-band bins
% (excluding a guard zone). Best for FM tonal calls.
%
% Note: per-bin SNR exceeds band-average SNR by ~10*log10(nBandBins).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 4. ridge ---\n');
[~, tlo] = galleryFig('4. Ridge method', nTypes, 4);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('ridge', spectroP{ct});
    snrTable(4,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 5. Synchrosqueeze method
% Uses the Fourier synchrosqueezed transform (FSST) to sharpen the
% time-frequency representation before ridge tracking. Reassigns energy
% from smeared TF bins towards the instantaneous frequency, giving crisper
% ridge localisation for rapidly FM signals. More expensive than standard
% ridge.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 5. synchrosqueeze ---\n');
[~, tlo] = galleryFig('5. Synchrosqueeze method', nTypes, 5);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('synchrosqueeze', spectroP{ct});
    snrTable(5,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 6. Quantiles method
% Estimates signal and noise within the signal window alone -- no separate
% noise window needed. Top 15% of spectrogram cells (by power) = signal;
% bottom 85% = noise, illustrated with percentile contour overlays.
% Useful when noise windows are unavailable (e.g. continuous calling bouts)
% but less accurate than window-based methods for isolated calls.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 6. quantiles ---\n');
[~, tlo] = galleryFig('6. Quantiles method (no noise window)', nTypes, 6);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('quantiles', spectroP{ct});
    snrTable(6,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7. NIST histogram method
% Implements the NIST STNR 'quick' algorithm (Ellis 2011), adapted for
% bioacoustics by bandpass filtering to the annotation band before
% computing 20 ms frame energies. Noise is estimated from the leftmost
% peak of the smoothed 500-bin histogram; signal from the 95th percentile.
%
% A bimodal histogram indicates reliable separation; a unimodal histogram
% (short clips, low SNR, or very high duty cycle) means the estimate
% should be treated with caution. The x-axis is in physical dB units
% (dBFS uncalibrated, or dB re 1 uPa if calibrated).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 7. nist ---\n');
[~, tlo] = galleryFig('7. NIST histogram method', nTypes, 7);
for ct = 1:nTypes
    nexttile(tlo);
    if ~available(ct), axis off; continue; end
    p = galleryParams('nist', spectroP{ct});
    snrTable(7,ct) = runAndTitle(annots{ct}, p, callTypes{ct,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 8. Lurton formula
% All methods support the Lurton (2010) SNR formula as an alternative to
% the simple power ratio:
%
%   SNR = 10*log10( (rmsSignal - rmsNoise)^2 / noiseVar )
%
% Used in Miller et al. (2021) for D-call detection probability estimation.
% Produces higher absolute SNR values than the simple ratio because it
% normalises the excess signal power by the noise variance.
% Spectrogram results are shown here with both formulas for comparison.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 8. Lurton formula ---\n');
fig8 = figure('Name','Lurton','Position',galleryFigPos(8, nTypes));
tlo8 = tiledlayout(fig8, 2, nTypes, 'TileSpacing','compact','Padding','compact');
title(tlo8, '8. Simple power ratio (top) vs Lurton formula (bottom)', ...
    'FontWeight','bold');

for ct = 1:nTypes
    nexttile(tlo8);
    if ~available(ct), axis off; nexttile(tlo8); axis off; continue; end
    p  = galleryParams('spectrogram', spectroP{ct});
    sS = runAndTitle(annots{ct}, p, sprintf('%s | simple', callTypes{ct,1}));

    nexttile(tlo8);
    p.useLurton = true;
    sL = runAndTitle(annots{ct}, p, sprintf('%s | Lurton', callTypes{ct,1}));
    fprintf('  %-10s  simple=%.1f dB  Lurton=%.1f dB\n', callTypes{ct,1}, sS, sL);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 9. Calibrated acoustic levels
% When instrument metadata is provided, bsnr converts outputs to
% calibrated dB re 1 uPa. The metadata struct specifies hydrophone
% sensitivity, ADC peak voltage, and the front-end frequency response
% curve. |simpleFlatMetadata()| models a representative instrument:
% flat 20 dB gain, -165 dB re V/uPa sensitivity, 1.5 V ADC peak.
%
% SNR is dimensionless and unchanged by calibration; absolute signal and
% noise levels shift by the calibration offset. Spectrogram colour axis
% and histogram x-axis both update to dB re 1 uPa automatically.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 9. calibrated levels ---\n');
ctCal = find(available, 1, 'first');
if ~isempty(ctCal)
    fig9 = figure('Name','calibration','Position',[50 50 800 340]);
    tlo9 = tiledlayout(fig9, 1, 2, 'TileSpacing','compact','Padding','compact');
    title(tlo9, '9. Calibrated vs uncalibrated levels', 'FontWeight','bold');

    nexttile(tlo9);
    p    = galleryParams('spectrogram', spectroP{ctCal});
    snrU = runAndTitle(annots{ctCal}, p, ...
        sprintf('%s  (dBFS)', callTypes{ctCal,1}));

    nexttile(tlo9);
    p.metadata = simpleFlatMetadata();
    snrC = runAndTitle(annots{ctCal}, p, ...
        sprintf('%s  (dB re 1 uPa)', callTypes{ctCal,1}));

    fprintf('  SNR: uncalibrated=%.1f dB  calibrated=%.1f dB  (should match)\n', ...
        snrU, snrC);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 10. Click removal
% Impulsive noise (airguns, sonar, biological clicks) inflates SNR
% estimates. |removeClicks| applies a PAMGuard-style soft amplitude gate:
% frames exceeding |threshold| x median RMS are attenuated by raising
% the envelope to the power |power| (default: threshold=3, power=1000).
% Illustrated on ABW D-calls, which are often measured alongside airguns
% in the Casey 2019 dataset.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 10. click removal ---\n');
ctClick = find(strcmp(callTypes(:,2), 'abw_d')' & available, 1);
if isempty(ctClick), ctClick = find(available, 1, 'first'); end

if ~isempty(ctClick)
    fig10 = figure('Name','click removal','Position',[50 50 800 340]);
    tlo10 = tiledlayout(fig10, 1, 2, 'TileSpacing','compact','Padding','compact');
    title(tlo10, '10. Click removal', 'FontWeight','bold');

    nexttile(tlo10);
    p    = galleryParams('spectrogram', spectroP{ctClick});
    snrN = runAndTitle(annots{ctClick}, p, ...
        sprintf('%s  (no click removal)', callTypes{ctClick,1}));

    nexttile(tlo10);
    p.removeClicks = struct('threshold', 3, 'power', 1000);
    snrK = runAndTitle(annots{ctClick}, p, ...
        sprintf('%s  (clicks removed)', callTypes{ctClick,1}));

    fprintf('  Without removal: %.1f dB   With removal: %.1f dB\n', snrN, snrK);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 11. Noise window strategies
% The noise window can be placed in several ways relative to the detection.
%
%   'beforeAndAfter'  -- symmetric, 0.5 s gap (default)
%   'before'          -- immediately before signal, no gap
%   '25sBefore'       -- 25 s window before signal (long-term background)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 11. noise window strategies ---\n');
ctNW = find(available, 1, 'first');
if ~isempty(ctNW)
    nwStrats = {'beforeAndAfter', 'before', '25sBefore'};
    fig11 = figure('Name','noise windows','Position',[50 50 280*3 340]);
    tlo11 = tiledlayout(fig11, 1, 3, 'TileSpacing','compact','Padding','compact');
    title(tlo11, '11. Noise window strategies', 'FontWeight','bold');
    for s = 1:3
        nexttile(tlo11);
        p = galleryParams('spectrogram', spectroP{ctNW});
        p.noiseDuration = nwStrats{s};
        p.noiseDelay    = 0.5;
        snrNW = runAndTitle(annots{ctNW}, p, ...
            sprintf('%s\n%s', callTypes{ctNW,1}, nwStrats{s}));
        fprintf('  %-20s  SNR=%.1f dB\n', nwStrats{s}, snrNW);
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 12. Method comparison
% SNR estimates (dB, simple power ratio) for all seven methods across all
% six call types. Methods differ in how they partition signal and noise
% power within the annotation time-frequency box.
%
% Ridge and synchrosqueeze report per-bin SNR, which exceeds band-average
% SNR by ~10*log10(nBandBins). All other methods report band-average SNR.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('\n--- 12. Method comparison ---\n');
validCols = find(available);
if ~isempty(validCols)
    colLabels = strrep(callTypes(validCols,1)', ' ', '_');
    t = array2table(snrTable(:, validCols), ...
        'RowNames', methodNames, 'VariableNames', colLabels);
    fprintf('\nSNR (dB, simple power ratio):\n');
    disp(t);

    % Colour-coded heatmap
    nV = numel(validCols);
    fig12 = figure('Name','comparison', ...
        'Position',[50 50 max(500, 120*nV+200) 300]);
    ax = axes(fig12);
    imagesc(ax, snrTable(:, validCols));
    colormap(ax, 'parula');
    cb = colorbar(ax);
    cb.Label.String = 'SNR (dB)';
    set(ax, 'XTick', 1:nV,       'XTickLabel', colLabels, ...
            'YTick', 1:nMethods, 'YTickLabel', methodNames, ...
            'TickLabelInterpreter', 'none', 'FontSize', 8);
    xtickangle(ax, 30);
    title(ax, '12. SNR by method and call type (dB)', 'FontWeight','bold');
    for r = 1:nMethods
        for c = 1:nV
            v = snrTable(r, validCols(c));
            if isfinite(v)
                text(ax, c, r, sprintf('%.1f', v), ...
                    'HorizontalAlignment','center', ...
                    'VerticalAlignment','middle', ...
                    'FontSize', 7, 'Color', 'w', 'FontWeight', 'bold');
            end
        end
    end
end

fprintf('\n=== gallery complete ===\n');
fprintf('Audio: Miller et al. (2021) doi:10.26179/5e6056035c01b\n');
fprintf('%d/%d call types available.\n', sum(available), nTypes);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function p = galleryParams(snrType, sp)
% Standard snrEstimate params struct for gallery use.
p = struct('snrType', snrType, 'showClips', true, ...
    'pauseAfterPlot', false, 'noiseDuration', 'beforeAndAfter', ...
    'noiseDelay', 0.5, 'spectroParams', sp);
end

function snr = runAndTitle(annot, p, titleStr)
% Run snrEstimate and set axis title with SNR value.
snr = snrEstimate(annot, p);
if istable(snr), snr = snr.snr; end
title(gca, sprintf('%s\n%.1f dB', titleStr, snr), ...
    'interpreter','none', 'FontSize',7);
fprintf('  %-22s  SNR = %.1f dB\n', titleStr, snr);
end

function [fig, tlo] = galleryFig(titleStr, nCols, idx)
% Create a tiled figure with standard layout.
fig = figure('Name', titleStr, 'Position', galleryFigPos(idx, nCols));
tlo = tiledlayout(fig, 1, nCols, 'TileSpacing','compact','Padding','compact');
title(tlo, titleStr, 'FontWeight','bold');
end

function pos = galleryFigPos(idx, nCols)
% Tile figures across and down the screen.
w = 260 * nCols;  h = 340;
row = mod(idx-1, 3);  col = floor((idx-1) / 3);
pos = [50 + col*50 + row*20, max(50, 950 - row*(h+50)), w, h];
end

function sp = gallerySpectroParams(spType, freq)
% Spectrogram display parameters appropriate for each call type.
switch spType
    case 'blue'  % narrow-band low-frequency tonal (ABW units, fin 20Hz)
        nfft = 4096;  noverlap = round(nfft*0.90);  highFreq = 80;
        pre = 3;  post = 3;
    case 'd'     % short broadband downsweep (ABW D, fin 40Hz)
        nfft = 512;   noverlap = round(nfft*0.75);  highFreq = 150;
        pre = 2;  post = 2;
    otherwise
        nfft = 1024;  noverlap = round(nfft*0.75);  highFreq = 200;
        pre = 2;  post = 2;
end
sp.win = nfft;  sp.overlap = noverlap;  sp.yLims = [0 highFreq];
sp.freq = freq;  sp.pre = pre;  sp.post = post;
end
