%% bsnr Gallery
% Illustrated reference for the bsnr SNR estimation toolbox.
%
% *Part 1* uses synthetic test fixtures to explain each feature and the
% conceptual differences between methods. Every section is self-contained:
% the fixture is built, the method is run, and the plot is drawn within
% that section alone.
%
% *Part 2* uses real Antarctic baleen whale recordings from the IWC-SORP
% Annotated Library (Miller et al. 2021) as functional demos, with
% spectrogram parameters matched to the published figures.
%
% Publish to PDF:
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
galleryDir = fileparts(mfilename('fullpath'));
audioDir   = fullfile(galleryDir, 'audio');
fprintf('\n=== bsnr gallery ===\n\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Path setup
% Add bsnr and its dependencies to the MATLAB path if not already present.
% Edit |analysisRoot| to match your local installation.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sourceDir = fileparts(galleryDir);          % bsnr root
addpath(sourceDir, '-begin');
addpath(galleryDir, '-begin');

analysisRoot = 'C:\analysis';
deps = {
    'longTermRecorders', fullfile(analysisRoot, 'longTermRecorders')
    'annotatedLibrary',  fullfile(analysisRoot, 'annotatedLibrary')
    'bsmTools',          fullfile(analysisRoot, 'bsmTools')
    'soundFolder',       fullfile(analysisRoot, 'soundFolder')
};
existingPaths = strsplit(path, pathsep);
for d = 1:size(deps, 1)
    depDir = deps{d, 2};
    if exist(depDir, 'dir') && ~any(strcmp(existingPaths, depDir))
        addpath(depDir);
        fprintf('Added: %s\n', deps{d, 1});
    end
end
% Re-assert bsnr at front so its versions take precedence over stale copies
addpath(sourceDir, '-begin');
addpath(galleryDir, '-begin');

% Add tests/ so createTestFixture, makeSRWUpcall etc. are available standalone
testsDir = fullfile(sourceDir, 'tests');
if exist(testsDir, 'dir') && ~any(strcmp(existingPaths, testsDir))
    addpath(testsDir, '-begin');
    fprintf('Added: tests/\n');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PART 1 — Synthetic fixtures: concepts and comparisons
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PART 1 — Synthetic fixtures: concepts and comparisons
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1. Noise window strategies
% The noise window placement affects how well the estimated noise level
% represents the true background at the time of the detection.
%
%   'beforeAndAfter'  — symmetric, 0.5 s gap each side (default)
%   'before'          — immediately before signal, no gap
%   '25sBefore'       — 25 s window placed before the detection
%
% For a stationary synthetic signal all three give similar SNR (as expected).
% The noise extent is shown in red on each spectrogram.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 1. noise window strategies ---\n');

noiseWinFreq    = [150 250];
noiseWinSP      = fixtureSP(2000, noiseWinFreq);
noiseWinSR      = 2000;
noiseWinDetDur  = 4;    % s
noiseWinPreBuf  = 32;   % s — needs 25+0.5+1+2 = 28.5 s before signal
noiseWinPostBuf = 5;    % s
noiseWinWbRMS   = 0.1 * sqrt(noiseWinSR/2 / diff(noiseWinFreq));

rng(71);
noiseWinDetTime  = (0:round(noiseWinDetDur*noiseWinSR)-1)' / noiseWinSR;
noiseWinDetAudio = 0.5*sin(2*pi*200*noiseWinDetTime) + noiseWinWbRMS*randn(round(noiseWinDetDur*noiseWinSR), 1);
noiseWinFullAudio = [noiseWinWbRMS * randn(round(noiseWinPreBuf  * noiseWinSR), 1); ...
                     noiseWinDetAudio; ...
                     noiseWinWbRMS * randn(round(noiseWinPostBuf * noiseWinSR), 1)];

[annotNW, cleanupNW] = audioToFixture(noiseWinFullAudio, noiseWinSR, noiseWinFreq, ...
    noiseWinDetDur, 'Tone: noise window comparison', noiseWinPreBuf);

fig7 = figure('Name', 'noise window strategies', 'Position', [50 900 1200 340]);
tlo7 = tiledlayout(fig7, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo7, 'Noise window placement strategies', 'FontWeight', 'bold');

noiseStrategies = {'beforeAndAfter', 'before', '25sBefore'};
preBuffers      = [1, 1, 2];     % display pre-buffer per strategy (s)
for s = 1:3
    nexttile(tlo7);
    paramsNW               = makeParams('spectrogram', noiseWinSP);
    paramsNW.noiseDuration = noiseStrategies{s};
    paramsNW.noiseDelay    = 0.5;
    % Cap pre-buffer for display so 25sBefore doesn't show a 28 s spectrogram
    spNW      = noiseWinSP;
    spNW.pre  = preBuffers(s);
    paramsNW.spectroParams = spNW;
    snrNW = runAndTitle(annotNW, paramsNW, noiseStrategies{s});
    fprintf('  %-20s  SNR=%.1f dB\n', noiseStrategies{s}, snrNW);
end
cleanupNW();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 2. Lurton formula vs simple power ratio
% The |useLurton| option uses Lurton (2010) eq. 6.26:
%
%   SNR_Lurton = 10*log10( (rmsSignal - rmsNoise)^2 / noiseVar )
%
% The default simple power ratio is:
%
%   SNR_simple = 10*log10( rmsSignal / rmsNoise )
%
% The Lurton formula emphasises the excess of signal above noise, normalised
% by noise variance. It gives systematically higher values and was used in
% Miller et al. (2021) for D-call detection probability estimation.
% Top row: simple ratio. Bottom row: Lurton formula.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 2. Lurton vs simple ---\n');

lurtonFreq    = [150 250];
lurtonSP      = fixtureSP(2000, lurtonFreq);
lurtonConfigs = {'Low SNR (0.1/0.1)', 0.1, 0.1; ...
                 'Moderate (0.5/0.1)', 0.5, 0.1; ...
                 'High SNR (1.0/0.1)', 1.0, 0.1};

fig5 = figure('Name', 'Lurton vs simple', 'Position', [50 520 1200 680]);
tlo5 = tiledlayout(fig5, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo5, 'Simple power ratio (top) vs Lurton formula (bottom)', 'FontWeight', 'bold');

for k = 1:3
    [annotL, cleanupL] = createTestFixture('sampleRate', 2000, 'durationSec', 4, ...
        'toneFreqHz', 200, 'freq', lurtonFreq, ...
        'signalRMS', lurtonConfigs{k,2}, 'noiseRMS', lurtonConfigs{k,3}, ...
        'classification', lurtonConfigs{k,1});

    nexttile(tlo5, k);        % row 1: simple
    snrSimple = runAndTitle(annotL, makeParams('spectrogram', lurtonSP), lurtonConfigs{k,1});

    nexttile(tlo5, k+3);      % row 2: Lurton
    paramsLurton           = makeParams('spectrogram', lurtonSP);
    paramsLurton.useLurton = true;
    snrLurton = runAndTitle(annotL, paramsLurton, [lurtonConfigs{k,1} ' | Lurton']);

    cleanupL();
    fprintf('  %s:  simple=%.1f dB  Lurton=%.1f dB\n', lurtonConfigs{k,1}, snrSimple, snrLurton);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 3. Calibrated acoustic levels
% When instrument metadata is provided, bsnr converts outputs to calibrated
% dB re 1 µPa. SNR is dimensionless and unchanged by calibration; absolute
% signal and noise levels shift by the calibration offset.
%
% The reference signal is a 122 dB re 1 µPa RMS tone at 100 Hz — the standard
% DIFAR sonobuoy calibration reference — in noise at 90 dB re 1 µPa.
% |createCalibratedTestFixture| models the AAD Kerguelen 2024 instrument:
%   Sensitivity: -165.9 dB re V/µPa
%   ADC peak: 1.5 V (3 V peak-to-peak, 16-bit)
%   Gain: ~20 dB flat 20-2000 Hz, AC coupling below 5 Hz
%
% The spectrogram colour axis shifts from dB re 1 V^2/Hz to dB re 1 µPa^2/Hz.
% The SNR value is identical before and after calibration.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 3. calibrated levels ---\n');

% Reference tone: 122 dB re 1 µPa RMS at 100 Hz in 90 dB re 1 µPa noise.
% 122 dB re 1 µPa is the standard DIFAR sonobuoy reference calibration level,
% representing a moderately loud low-frequency cetacean call.
% The instrument chain (sensitivity=-165.9 dB re V/µPa, gain=20 dB, ADC=1.5 V peak)
% maps this to approximately -26.5 dBFS in the WAV file.
% After calibration, the spectrogram colour axis shifts from dB re 1 V^2/Hz
% to dB re 1 µPa^2/Hz; the SNR is identical in both cases.
[annotCal, calMetadata, cleanupCal] = createCalibratedTestFixture( ...
    'signalLeveldB', 122, 'noiseLeveldB', 90, ...
    'toneFreqHz', 100, 'freq', [80 120], 'durationSec', 4, ...
    'classification', '122 dB re 1 µPa tone at 100 Hz');

calSP = struct('win', 512, 'overlap', 384, 'yLims', [0 300], ...
    'freq', [80 120], 'pre', 1, 'post', 1);

figCal = figure('Name', 'calibration', 'Position', [50 520 800 340]);
tloCal = tiledlayout(figCal, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tloCal, 'Uncalibrated (dB re 1 V^2/Hz) vs calibrated (dB re 1 µPa^2/Hz)', ...
    'FontWeight', 'bold');

nexttile(tloCal);
snrUncal = runAndTitle(annotCal, makeParams('spectrogram', calSP), 'Uncalibrated');

nexttile(tloCal);
paramsCal          = makeParams('spectrogram', calSP);
paramsCal.metadata = calMetadata;
snrCal = runAndTitle(annotCal, paramsCal, 'Calibrated (dB re 1 µPa)');

fprintf('  SNR: uncalibrated=%.1f dB  calibrated=%.1f dB  (should match)\n', snrUncal, snrCal);
cleanupCal();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 4. Click removal
% Impulsive noise inflates SNR estimates by raising the measured noise
% or signal power. |removeClicks| applies a PAMGuard-style soft amplitude
% gate: frames exceeding |threshold| x median RMS are attenuated by
% raising the envelope to the power |power| (< 1).
%
% Synthetic clicks are 5 ms in-band sine bursts at amplitude=30, spaced
% 0.5 s apart in the detection window — well above the removal threshold.
%
% Left: raw spectrogram and inflated SNR estimate.
% Right: after click removal (threshold=3, power=1000) — spectrogram shows
%        cleaned audio and SNR recovers toward the true value.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 4. click removal ---\n');

clickFreq    = [150 250];
clickSP      = fixtureSP(2000, clickFreq);
clickBufDur  = 5;       % s
clickDetDur  = 4;       % s
clickSR      = 2000;

clickWidebandRMS  = 0.1 * sqrt(clickSR/2 / diff(clickFreq));
clickNBuf         = round(clickBufDur * clickSR);
clickNDet         = round(clickDetDur * clickSR);

rng(61);
clickDetTime  = (0:clickNDet-1)' / clickSR;
clickNoiseBuf2 = clickWidebandRMS * randn(clickNBuf, 1);
% Signal with in-band click bursts every 0.5 s (5 ms, amplitude=30)
clickDetAudio = 0.5*sin(2*pi*200*clickDetTime) + clickWidebandRMS*randn(clickNDet, 1);
clickBurstDur  = round(0.005 * clickSR);   % 5 ms
clickBurstTime = (0:clickBurstDur-1)' / clickSR;
clickBurstAmp  = 30 * sin(2*pi*200*clickBurstTime);
for clickStart = round((0.5:0.5:clickDetDur-0.5) * clickSR)
    clickRange = clickStart : clickStart + clickBurstDur - 1;
    clickDetAudio(clickRange) = clickDetAudio(clickRange) + clickBurstAmp;
end

[annotClicks, cleanupClicks] = audioToFixture( ...
    [clickNoiseBuf2; clickDetAudio; clickNoiseBuf2], clickSR, clickFreq, clickDetDur, ...
    'Tone + in-band clicks every 0.5 s (amplitude=30)', clickBufDur);

fig6 = figure('Name', 'click removal', 'Position', [50 140 800 340]);
tlo6 = tiledlayout(fig6, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo6, 'Click removal (threshold=3, power=1000)', 'FontWeight', 'bold');

nexttile(tlo6);
snrNoRemoval = runAndTitle(annotClicks, makeParams('spectrogram', clickSP), ...
    'Without click removal');

nexttile(tlo6);
paramsWithRemoval               = makeParams('spectrogram', clickSP);
paramsWithRemoval.removeClicks  = struct('threshold', 3, 'power', 1000);
snrWithRemoval = runAndTitle(annotClicks, paramsWithRemoval, 'With click removal');

fprintf('  Without: %.1f dB    With: %.1f dB\n', snrNoRemoval, snrWithRemoval);
cleanupClicks();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 5. Effect of nSlices on the spectrogram and SNR estimate
% |params.nSlices| (default: 30) sets the STFT window width:
%   nfft = 2^nextpow2(duration / nSlices / 0.75 * sampleRate)
%
% Fewer slices -> wider windows -> finer frequency resolution -> narrower
% spectral peak for a tone -> smaller noiseVar per slice (variance of band
% power scales with df = sampleRate/nfft, so wider windows give smaller
% per-slice variance).  More slices -> shorter windows -> coarser frequency
% resolution -> broader spectral peak -> larger noiseVar per slice.
%
% For the simple power ratio the SNR is stable across all nSlices values
% because the mean band power (signal + noise) is nearly nfft-independent.
% For the Lurton formula SNR = (S-N)^2/noiseVar, the decreasing noiseVar
% with fewer slices drives the Lurton SNR upward.
%
% Critically, the displayed spectrogram now uses the SAME nfft as the
% computation — so you can see the window becoming wider (coarser time,
% finer frequency) as nSlices decreases.  This is the correct diagnostic
% view: the plot always reflects what was actually measured.
%
% Four columns: nSlices = 5, 15, 30 (default), 60.
% Top row: simple power ratio (stable).
% Bottom row: Lurton formula (higher with fewer slices due to smaller noiseVar).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 5. nSlices effect on spectrogram and SNR ---\n');

nSlicesValues = [5, 15, 30, 60];
nSlicesLabels = {'nSlices=5', 'nSlices=15', 'nSlices=30 (default)', 'nSlices=60'};
nSlicesFreq   = [150 250];

[annotNSlices, cleanupNSlices] = createTestFixture('sampleRate', 2000, 'durationSec', 10, ...
    'toneFreqHz', 200, 'freq', nSlicesFreq, 'signalRMS', 0.5, 'noiseRMS', 0.1, ...
    'classification', 'Tone (10 s, signalRMS=0.5, noiseRMS=0.1)');

figNSlices = figure('Name', 'nSlices', 'Position', [50 900 1200 680]);
tloNSlices = tiledlayout(figNSlices, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tloNSlices, 'nSlices — spectrogram window matches computation; Lurton SNR reflects noiseVar', ...
    'FontWeight', 'bold');

fprintf('  %-24s  %8s  %8s\n', 'nSlices', 'simple', 'Lurton');
for k = 1:4
    % Do NOT pass spectroParams — let buildSpectroParams derive nfft from nSlices
    % so the displayed spectrogram uses the same window as the SNR computation.
    paramsSimple           = struct('snrType', 'spectrogram', 'showClips', true, ...
        'pauseAfterPlot', false, 'noiseDuration', 'beforeAndAfter', 'noiseDelay', 0.5, ...
        'nSlices', nSlicesValues(k));
    paramsLurton           = paramsSimple;
    paramsLurton.useLurton = true;

    nexttile(tloNSlices, k);       % row 1: simple
    snrSimple = runAndTitle(annotNSlices, paramsSimple, nSlicesLabels{k});

    nexttile(tloNSlices, k+4);     % row 2: Lurton
    snrLurton = runAndTitle(annotNSlices, paramsLurton, [nSlicesLabels{k} ' | Lurton']);

    fprintf('  %-24s  %8.1f  %8.1f\n', nSlicesLabels{k}, snrSimple, snrLurton);
end
cleanupNSlices();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 6. Stationary tone vs pulsed signal — duty cycle and mean-power SNR
% All mean-power methods (spectrogram, spectrogramSlices, timeDomain) average
% signal power over the entire annotation window, including any silent gaps.
% For a pulsed call like the Antarctic minke whale bio-duck, the annotation
% covers the whole bout rather than individual pulses.  The mean power is
% therefore diluted by the inter-pulse gaps, giving a lower SNR than would
% be measured on a single pulse.
%
% This is not a flaw — it accurately reflects the detection challenge:
% a passive detector sees the mean energy in its integration window.
%
% Three panels at the same peak pulse RMS (0.5):
%   Continuous tone — no gaps, full power throughout annotation
%   Pulsed tone (50%% duty cycle) — same peak, half the mean power (~3 dB lower)
%   Bio-duck bout — realistic A1 call structure (~9%% duty cycle, ~10 dB lower)
%
% The ridge method (Section 2) is not affected by duty cycle because it
% measures power at the instantaneous ridge frequency, not the window mean.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 6. duty cycle and mean-power SNR ---\n');

dutyCycleFreq = [150 250];
dutyCycleSP   = fixtureSP(2000, dutyCycleFreq);

% 1. Continuous tone
[annotCont, cleanupCont] = createTestFixture('sampleRate', 2000, 'durationSec', 10, ...
    'toneFreqHz', 200, 'freq', dutyCycleFreq, 'signalRMS', 0.5, 'noiseRMS', 0.1, ...
    'classification', 'Continuous tone (100% duty cycle)');

% 2. Pulsed tone at 50% duty cycle — same peak amplitude, half the mean power
% Built manually: tone alternates on/off in 0.5 s blocks
rng(21);
pulseSR      = 2000;
pulseDur     = 10;
pulseBufDur  = 7;    % s each side
pulseWbRMS   = 0.1 * sqrt(pulseSR/2 / diff(dutyCycleFreq));
nPulseDet    = round(pulseDur * pulseSR);
pulseTime    = (0:nPulseDet-1)' / pulseSR;
pulsedTone   = 0.5 * sin(2*pi*200*pulseTime);
% Zero out every other 0.5 s block (50% duty cycle)
blockSamples = round(0.5 * pulseSR);
for b = 1:2:floor(nPulseDet/blockSamples)
    offIdx = (b-1)*blockSamples+1 : min(b*blockSamples, nPulseDet);
    pulsedTone(offIdx) = 0;
end
pulseDetAudio = pulsedTone + pulseWbRMS * randn(nPulseDet, 1);
pulseBuf      = pulseWbRMS * randn(round(pulseBufDur*pulseSR), 1);
[annotPulsed, cleanupPulsed] = audioToFixture( ...
    [pulseBuf; pulseDetAudio; pulseBuf], pulseSR, dutyCycleFreq, pulseDur, ...
    'Pulsed tone 50% duty cycle (0.5 s on/off)', pulseBufDur);

% 3. Bio-duck bout — A1 parameters (Dominello & Sirovic 2016)
[annotBioduck, cleanupBioduck] = createTestFixture('sampleRate', 1000, 'durationSec', 20, ...
    'signalType', 'bioduck', 'freqHigh', 200, 'freqLow', 60, ...
    'pulseDuration', 0.10, 'pulseInterval', 0.30, ...
    'pulsesPerSeries', 4, 'seriesInterval', 3.10, ...
    'signalRMS', 0.5, 'noiseRMS', 0.1, ...
    'freq', [30 250], ...
    'classification', 'Bio-duck A1 bout (~9% duty cycle)');
bioduckSP = struct('win', 256, 'overlap', 230, 'yLims', [0 300], ...
    'freq', [30 250], 'pre', 1, 'post', 1);

figDuty = figure('Name', 'duty cycle', 'Position', [50 520 1200 340]);
tloDuty = tiledlayout(figDuty, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tloDuty, 'Duty cycle — mean-power SNR reflects window-averaged energy, not peak pulse SNR', ...
    'FontWeight', 'bold');

nexttile(tloDuty);
snrCont    = runAndTitle(annotCont,    makeParams('spectrogram', dutyCycleSP),  'Continuous tone');
nexttile(tloDuty);
snrPulsed  = runAndTitle(annotPulsed,  makeParams('spectrogram', dutyCycleSP),  'Pulsed 50% duty cycle');
nexttile(tloDuty);
snrBioduck = runAndTitle(annotBioduck, makeParams('spectrogram', bioduckSP),    'Bio-duck A1 (~9% duty)');

fprintf('  Continuous:    %.1f dB\n', snrCont);
fprintf('  Pulsed 50%%:    %.1f dB  (expected ~%.1f dB, i.e. -3 dB)\n', snrPulsed, snrCont-3);
fprintf('  Bio-duck  9%%:  %.1f dB  (expected ~%.1f dB, i.e. -10 dB)\n', snrBioduck, snrCont-10);
cleanupCont(); cleanupPulsed(); cleanupBioduck();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7. Distribution-based methods — quantiles and NIST histogram
% Both methods estimate SNR from an energy distribution rather than comparing
% separate signal and noise windows.
%
% |quantiles| splits the 2D distribution of spectrogram TF cell PSD values
% within the signal window: the top 15% of cells by power are 'signal';
% the bottom 85% are 'noise'.  No separate noise window is needed.
%
% The NIST method computes a 1D histogram of wideband 20 ms frame energies
% pooled from both noise and signal windows, then estimates noise from the
% leftmost histogram peak (raised cosine fit) and signal from the 95th
% percentile of the residual.
%
% Both methods show two display views:
%   Top row    — spectrogram with contour lines at the estimated noise and
%                signal PSD thresholds (iso-power contours, like quantile contours)
%   Bottom row — histogram of the underlying distribution with vertical lines
%                at the estimated noise and signal levels
%
% The parallel display makes the conceptual relationship clear:
% quantiles uses TF cells from the signal window only (2D distribution);
% NIST uses time-domain frames from both windows (1D distribution).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7a. Quantiles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 7a/7b. quantiles and NIST (SRW upcall) ---\n');

% Both sections use makeSRWUpcall — the same helper and signal parameters
% as section 8 (ridge/synchrosqueeze):
%   f(t) = 80 + 118*t^2 Hz,  1 s,  1000 Hz,  band [75 210] Hz
% The SRW upcall's diagonal TF streak is more illustrative than a tone:
% iso-power contours track the streak by power level, not by frequency,
% which is the key concept for both quantiles and NIST.
% NIST pools noise + signal frames: 1 s signal + ~2 s noise window = ~300
% frames, well above the 10-frame minimum for a smooth histogram.
srwFreq   = [75 210];
srwBufDur = 4;    % s each side
srwSP     = struct('win', 128, 'overlap', 96, 'yLims', [0 250], ...
    'freq', srwFreq, 'pre', 1, 'post', 1);

distConfigs = {'Noise only', 0.0, 0.1; 'Moderate SNR', 0.3, 0.1; 'High SNR', 1.0, 0.1};
nDist       = size(distConfigs, 1);

% Pre-build fixtures so 7a and 7b share exactly the same WAV files.
srwAnnots   = cell(nDist, 1);
srwCleanups = cell(nDist, 1);
srwWbRMS    = 0.1 * sqrt(500 / diff(srwFreq));
nBuf        = round(srwBufDur * 1000);
rng(71);
for k = 1:nDist
    sigRMS       = distConfigs{k,2};
    [sweep, ~]   = makeSRWUpcall(1000, 0.0);   % unit-amplitude sweep, no noise
    detAudio     = sigRMS * sweep + srwWbRMS * randn(length(sweep), 1);
    noiseBuf     = srwWbRMS * randn(nBuf, 1);
    [srwAnnots{k}, srwCleanups{k}] = audioToFixture( ...
        [noiseBuf; detAudio; noiseBuf], 1000, srwFreq, 1.0, ...
        distConfigs{k,1}, srwBufDur);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7a. Quantiles
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

figQ = figure('Name', 'quantiles', 'Position', [50 140 900 680]);
tloQ = tiledlayout(figQ, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tloQ, '7a. Quantiles — spectrogram contours (top) and TF cell PSD histogram (bottom)', ...
    'FontWeight', 'bold');

for k = 1:nDist
    nexttile(tloQ, k);
    snrQ = runAndTitle(srwAnnots{k}, makeParams('quantiles', srwSP), distConfigs{k,1});

    nexttile(tloQ, k+nDist);
    paramsQhist              = makeParams('quantiles', srwSP);
    paramsQhist.quantDisplay = 'histogram';
    runAndTitle(srwAnnots{k}, paramsQhist, [distConfigs{k,1} ' | histogram']);

    fprintf('  %s: %.1f dB\n', distConfigs{k,1}, snrQ);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 7b. NIST histogram
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 7b. NIST ---\n');

figN = figure('Name', 'NIST histogram', 'Position', [50 900 900 680]);
tloN = tiledlayout(figN, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tloN, '7b. NIST — spectrogram contours (top) and frame-energy histogram (bottom)', ...
    'FontWeight', 'bold');

for k = 1:nDist
    nexttile(tloN, k);
    paramsNspec             = makeParams('nist', srwSP);
    paramsNspec.nistDisplay = 'spectrogram';
    snrN = runAndTitle(srwAnnots{k}, paramsNspec, distConfigs{k,1});

    nexttile(tloN, k+nDist);
    runAndTitle(srwAnnots{k}, makeParams('nist', []), [distConfigs{k,1} ' | histogram']);

    fprintf('  %s: %.1f dB\n', distConfigs{k,1}, snrN);
end

for k = 1:nDist, srwCleanups{k}(); end

%% 8. Ridge and synchrosqueeze — FM signal
% The |ridge| method tracks the dominant instantaneous frequency using
% |tfridge|, taking power from the single FFT bin on the ridge at each
% time step.  |synchrosqueeze| first sharpens the TF representation via
% the Fourier synchrosqueezed transform (FSST) before tracking.
%
% Both are shown on a synthetic Southern Right Whale upcall:
%   f(t) = 80 + 118*t^2  Hz  (0 to 1 s, reaching ~198 Hz)
%
% Because signal power is concentrated at one bin and noise is averaged
% across all other in-band bins, per-bin SNR exceeds band-average SNR by
% ~10*log10(nBandBins).  The cyan overlay shows the tracked ridge.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 9. ridge and synchrosqueeze (SRW upcall) ---\n');

srwSampleRate = 1000;
srwFreqBand   = [75 210];
srwDuration   = 1.0;    % s
srwBufDur     = 3;      % s each side

[srwSignal, ~] = makeSRWUpcall(srwSampleRate, 0.1);

rng(11);
srwWidebandRMS = 0.1 * sqrt(srwSampleRate/2 / 135);   % 135 Hz bandwidth
srwBufSamples  = round(srwBufDur * srwSampleRate);
srwNoiseBuf    = srwWidebandRMS * randn(srwBufSamples, 1);
srwFullAudio   = [srwNoiseBuf; srwSignal; srwNoiseBuf];
srwFullAudio   = srwFullAudio * (0.9 / max(abs(srwFullAudio)));

[annotSRW, cleanupSRW] = audioToFixture(srwFullAudio, srwSampleRate, srwFreqBand, ...
    srwDuration, 'SRW upcall  f(t)=80+118t^2 Hz', srwBufDur);

srwSpectroDisp = struct('win', round(srwSampleRate/6), ...
    'overlap', round(srwSampleRate/6*0.90), ...
    'yLims', [0 250], 'freq', srwFreqBand, 'pre', 1, 'post', 1);

fig2 = figure('Name', 'ridge + synchrosqueeze', 'Position', [50 520 800 340]);
tlo2 = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo2, 'Ridge and synchrosqueeze on SRW upcall  f(t) = 80+118t^2 Hz', 'FontWeight', 'bold');

nexttile(tlo2);
snrRidge = runAndTitle(annotSRW, makeParams('ridge', srwSpectroDisp), 'ridge (per-bin SNR)');
nexttile(tlo2);
snrSSQ   = runAndTitle(annotSRW, makeParams('synchrosqueeze', srwSpectroDisp), 'synchrosqueeze (FSST ridge)');
fprintf('  ridge=%.1f dB  synchrosqueeze=%.1f dB\n', snrRidge, snrSSQ);
fprintf('  (Per-bin SNR ~ band-average + 10*log10(nBandBins))\n');
cleanupSRW();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PART 2 — Real recordings: functional demos
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Call type definitions.
% t0InClip_s: annotation start time within the pre-extracted clip (s).
% Adjusted from the original 10 s default to centre the call in the window.
%
%   label | subdir | t0InClip_s | duration_s | freq_Hz
callTypes = {
  'ABW A'    'abw_a'  10   10   [24  28]    % no shift
  'ABW B'    'abw_b'  13   12   [20  28]    % +3 s from original
  'ABW Z'    'abw_z'  12   21   [17  28]    % +2 s from original
  'ABW D'    'abw_d'  11    4   [44  72]    % +1 s
  'Fin 40Hz' 'bp_40'   8    2   [32  61]    % -2 s
  'Fin 20Hz' 'bp_20'   7    4   [15  35]    % -3 s; duration +2 s for FIR headroom
};
nCallTypes = size(callTypes, 1);

callAnnots    = cell(nCallTypes, 1);
callSpectroP  = cell(nCallTypes, 1);
callAvailable = false(nCallTypes, 1);

for ct = 1:nCallTypes
    wavDir = fullfile(audioDir, callTypes{ct,2});
    if ~exist(wavDir, 'dir'), continue; end
    sf = wavFolderInfo(wavDir, '', false, false);   % verbose=false: no output
    callAnnot.soundFolder    = wavDir;
    callAnnot.t0             = sf(1).startDate + callTypes{ct,3}/86400;
    callAnnot.tEnd           = callAnnot.t0 + callTypes{ct,4}/86400;
    callAnnot.duration       = callTypes{ct,4};
    callAnnot.freq           = callTypes{ct,5};
    callAnnot.channel        = 1;
    callAnnot.classification = callTypes{ct,1};
    callAnnots{ct}    = callAnnot;
    callSpectroP{ct}  = realCallSP(callTypes{ct,2}, callTypes{ct,5});
    callAvailable(ct) = true;
end

if ~any(callAvailable)
    fprintf('\nNo real audio found — skipping Part 2.\n');
    fprintf('Run prepareGalleryAudio.m first.\n');
    return;
end

availableIdx = find(callAvailable);
nAvailable   = numel(availableIdx);
fprintf('\n--- Part 2: real recordings (%d/%d call types available) ---\n', ...
    nAvailable, nCallTypes);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 9. Real calls — all methods per call type
% One figure per call type, showing all seven methods as rows.
% This layout answers the practical question: given this specific call,
% what does each method estimate?
%
% Methods (rows):
%   spectrogram | spectrogramSlices | timeDomain | ridge |
%   synchrosqueeze | quantiles | nist
%
% All rows share a time axis. NIST is shown with spectrogram contours
% at the estimated noise and signal PSD levels (params.nistDisplay='spectrogram').
%
% Spectrogram display parameters are matched to Miller et al. (2021)
% published figures for each call type.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- 10. real calls — all methods ---\n');

methodNames = {'spectrogram', 'spectrogramSlices', 'timeDomain', ...
               'ridge', 'synchrosqueeze', 'quantiles', 'nist'};
nMethods   = numel(methodNames);
snrByMethod = nan(nMethods, nCallTypes);

for ct = availableIdx'
    callLabel = callTypes{ct, 1};
    fprintf('  %s\n', callLabel);

    figReal = figure('Name', sprintf('%s — all methods', callLabel), ...
        'Position', [50 50 280 nMethods*160]);
    tloReal = tiledlayout(figReal, nMethods, 1, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(tloReal, sprintf('%s — all methods', callLabel), 'FontWeight', 'bold');
    xlabel(tloReal, 'Time (s)', 'FontSize', 8);   % shared x-label on tiledlayout

    for mi = 1:nMethods
        nexttile(tloReal);
        if strcmp(methodNames{mi}, 'nist')
            % Use spectrogram display for NIST so all rows share a time axis.
            % The NIST noise-peak and signal-level contours are drawn on the
            % spectrogram, consistent with the quantiles contour display.
            paramsNist              = makeParams('nist', callSpectroP{ct});
            paramsNist.nistDisplay  = 'spectrogram';
            snrByMethod(mi, ct) = runAndTitle(callAnnots{ct}, paramsNist, methodNames{mi});
        else
            snrByMethod(mi, ct) = runAndTitle(callAnnots{ct}, ...
                makeParams(methodNames{mi}, callSpectroP{ct}), methodNames{mi});
        end
        % Remove per-axis xlabel (pushed to tiledlayout) and the
        % auto-generated classification+datestr title from spectroAnnotationAndNoise
        % (the tiledlayout title carries the call name already).
        xlabel(gca, '');
        if mi > 1
            % Only keep the classification title on the first row to save space;
            % subsequent rows just show the method name from runAndTitle.
            % spectroAnnotationAndNoise sets its own title — overwrite it.
            title(gca, methodNames{mi}, 'interpreter', 'none', 'FontSize', 7);
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 10. Method comparison — real calls
% SNR estimates (dB, simple power ratio) for all seven methods across all
% available call types, shown as a printed table and a colour-coded heatmap.
%
% Ridge and synchrosqueeze report per-bin SNR, which exceeds band-average
% SNR by ~10*log10(nBandBins) and is not directly comparable to the other
% methods.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('\n--- 11. method comparison ---\n');

colLabels = strrep(callTypes(availableIdx, 1)', ' ', '_');
snrTable  = array2table(snrByMethod(:, availableIdx), ...
    'RowNames', methodNames, 'VariableNames', colLabels);
fprintf('\nSNR (dB, simple power ratio):\n');
disp(snrTable);

fig11real = figure('Name', 'comparison heatmap', ...
    'Position', [50 50 max(500, 120*nAvailable+200) 300]);
axHeatmap = axes(fig11real);
imagesc(axHeatmap, snrByMethod(:, availableIdx));
colormap(axHeatmap, 'parula');
heatmapCB = colorbar(axHeatmap);
heatmapCB.Label.String = 'SNR (dB)';
set(axHeatmap, 'XTick', 1:nAvailable, 'XTickLabel', colLabels, ...
               'YTick', 1:nMethods,   'YTickLabel', methodNames, ...
               'TickLabelInterpreter', 'none', 'FontSize', 8);
xtickangle(axHeatmap, 30);
title(axHeatmap, 'SNR by method and call type (dB)', 'FontWeight', 'bold');
for row = 1:nMethods
    for col = 1:nAvailable
        cellValue = snrByMethod(row, availableIdx(col));
        if isfinite(cellValue)
            text(axHeatmap, col, row, sprintf('%.1f', cellValue), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontSize', 7, 'Color', 'w', 'FontWeight', 'bold');
        end
    end
end

fprintf('\n=== gallery complete ===\n');
fprintf('Audio: Miller et al. (2021) doi:10.26179/5e6056035c01b\n');
fprintf('%d/%d real call types available.\n', sum(callAvailable), nCallTypes);

%% Local helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function snrValue = runAndTitle(annot, params, titleStr)
% Run snrEstimate, annotate the current axis with the method name, return SNR.
snrValue = snrEstimate(annot, params);
if istable(snrValue), snrValue = snrValue.snr; end
title(gca, titleStr, 'interpreter', 'none', 'FontSize', 7);
fprintf('    %-32s  SNR = %.1f dB\n', titleStr, snrValue);
end

function params = makeParams(snrType, spectroDisp)
% Build a standard snrEstimate params struct.
% Pass spectroDisp=[] for methods that draw their own plot (e.g. nist).
params = struct('snrType', snrType, 'showClips', true, 'pauseAfterPlot', false, ...
    'noiseDuration', 'beforeAndAfter', 'noiseDelay', 0.5);
if ~isempty(spectroDisp)
    params.spectroParams = spectroDisp;
end
end

function [annot, cleanupFn] = audioToFixture(audioData, sampleRate, freqBand, ...
        detDurSec, label, detOffsetSec)
% Write an audio array to a temp WAV and return a bsnr annotation struct.
% detOffsetSec: seconds from file start to detection start.
if nargin < 6 || isempty(detOffsetSec)
    detOffsetSec = (length(audioData)/sampleRate - detDurSec) / 2;
end
tmpDir = fullfile(tempdir, sprintf('bsnr_gallery_%s', ...
    datestr(now, 'yyyymmdd_HHMMSS_FFF')));
mkdir(tmpDir);
fileStartDatenum = floor(now*86400) / 86400;
wavFilename      = [datestr(fileStartDatenum, 'yyyy-mm-dd_HH-MM-SS') '.wav'];
audioPeak = max(abs(audioData));
if audioPeak > 0
    audioData = audioData * (0.9 / audioPeak);
end
audiowrite(fullfile(tmpDir, wavFilename), audioData, sampleRate);
annot.soundFolder    = tmpDir;
annot.t0             = fileStartDatenum + detOffsetSec / 86400;
annot.tEnd           = annot.t0 + detDurSec / 86400;
annot.duration       = detDurSec;
annot.freq           = freqBand;
annot.channel        = 1;
if nargin >= 5 && ~isempty(label)
    annot.classification = label;
end
cleanupFn = @() rmdir(tmpDir, 's');
end

function spectroParams = fixtureSP(sampleRate, freqBand)
% Spectrogram display params for synthetic fixtures.
winLen = floor(sampleRate / 4);
spectroParams = struct('win', winLen, 'overlap', floor(winLen*0.75), ...
    'yLims', [0 sampleRate/2*0.6], 'freq', freqBand, 'pre', 1, 'post', 1);
end

function spectroParams = realCallSP(subdir, freqBand)
% Spectrogram display params for real calls at 250 Hz, matched to
% Miller et al. (2021) published figure parameters.
% ABW A/B use nfft=512 (not 256) to give sufficient frequency bins for
% the ridge method in their 4 Hz band ([24-28] and [20-28] Hz).
switch subdir
    case {'abw_a', 'abw_b'}              % very narrow tonal: more bins needed for ridge
        spectroParams = struct('win', 512, 'overlap', 460, 'yLims', [0 60], ...
            'freq', freqBand, 'pre', 3, 'post', 3);
    case 'abw_z'                         % narrow tonal, wider band than A/B
        spectroParams = struct('win', 256, 'overlap', 230, 'yLims', [0 80], ...
            'freq', freqBand, 'pre', 3, 'post', 3);
    case {'abw_d', 'bp_40'}              % short broadband
        spectroParams = struct('win', 128, 'overlap', 115, 'yLims', [0 125], ...
            'freq', freqBand, 'pre', 2, 'post', 2);
    case 'bp_20'                         % very low frequency narrow tonal
        spectroParams = struct('win', 256, 'overlap', 230, 'yLims', [0 80], ...
            'freq', freqBand, 'pre', 3, 'post', 3);
    otherwise
        spectroParams = struct('win', 256, 'overlap', 230, 'yLims', [0 100], ...
            'freq', freqBand, 'pre', 2, 'post', 2);
end
end
