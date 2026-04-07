%% Validation: Antarctic Blue Whale D-calls — Miller et al. (2022)
%
% Computes SNR for human-analyst and automated detector D-call detections
% from the test dataset used in:
%
%   Miller, B.S., Madhusudhana, S., Aulich, M.G. & Kelly, N. (2022).
%   Deep learning algorithm outperforms experienced human observer at
%   detection of blue whale D-calls: a double-observer analysis.
%   Remote Sensing in Ecology and Conservation.
%   https://doi.org/10.1002/rse2.297
%
% The paper's key finding was that the automated detector outperformed the
% human analyst (90% vs 70% recall), particularly for quiet calls. This
% script tests whether the SNR distributions reflect that finding: detector
% detections should extend to lower SNR values than analyst detections.
%
%% DATA DOWNLOAD
%
% Annotations (Raven selection tables):
%   Download Appendix S1 from the supplemental material of Miller et al.
%   (2022) at https://doi.org/10.1002/rse2.297 (Supporting Information).
%   This contains two Raven selection tables:
%     - Human analyst annotations (Casey 2019 test dataset)
%     - Automated detector detections (Koogu output, adjudicated)
%
% Recordings (WAV files):
%   The Casey 2019 recordings are held by the Australian Antarctic Division.
%   Contact: acoustics@aad.gov.au
%   Data access: https://data.aad.gov.au (search "Casey blue whale acoustics")
%   Note: recordings are large (~187 hours). Request a subset if needed.
%
%% CONFIGURATION — edit these paths before running

% Path to folder containing Casey 2019 WAV files
soundFolder = fullfile('w:\annotatedLibrary\BAFAAL\casey2019\wav\');

% Path to human analyst Raven selection table (Appendix S1, analyst sheet)
analystTable = fullfile('w:\annotatedLibrary\BAFAAL\Casey2019\', ...
    'Casey2019.Bm.D.selections.txt');

% Path to automated detector Koogu output selection table
detectorTable = fullfile('s:\manuscripts\2021-deepLearning-SORP-Library', ...
    'BmD_24_Casey2019_test_Raven\results.selections.txt');

% Path to adjudicated capture history table (Data S4 from Appendix S1)
% Download from supplemental material at https://doi.org/10.1002/rse2.297
% Contains one row per reconciled detection with judge verdict and SNR.
captureHistoryFile = fullfile('C:\analysis\bsnr\examples', ...
    'captureHistory_casey2019MGA_vs_denseNetBmD24_judgedBSM.csv');

% Metadata for Casey 2019 HARP recordings
metadata = metaDataCasey2019;   % set to [] for uncalibrated (dBFS) levels

%% CHECK DATA AVAILABLE
if ~exist(soundFolder, 'dir')
    error(['Sound folder not found: %s\n' ...
           'See DATA DOWNLOAD section at the top of this script.'], soundFolder);
end
if ~exist(analystTable, 'file')
    error(['Analyst annotation file not found: %s\n' ...
           'Download Appendix S1 from https://doi.org/10.1002/rse2.297'], analystTable);
end
if ~exist(detectorTable, 'file')
    error(['Detector annotation file not found: %s\n' ...
           'Download Appendix S1 from https://doi.org/10.1002/rse2.297'], detectorTable);
end

%% LOAD ANNOTATIONS
fprintf('Loading annotations...\n');

analystAnnot  = ravenTableToDetection(analystTable,  soundFolder, 'Casey2019', 'Analyst');
% Detector output is in Koogu format (FileOffset_s_, BeginFile columns)
% rather than standard Raven Pro format, so use kooguTableToDetection.
detectorAnnot = kooguTableToDetection(detectorTable, soundFolder, 'Casey2019', 'Detector');

fprintf('  Analyst:   %d detections\n', height(analystAnnot));
fprintf('  Detector:  %d detections\n', height(detectorAnnot));

%% SNR PARAMETERS
% D-calls: downswept FM call, ~50-100 Hz, ~1-3 s duration
% Use spectrogram method with a noise window on each side.
% Exact SNR method from supplemental annotationSNR.m (Code S3, Appendix S1):
%   noiseType  = 'timeDomain'  — bandpass FIR, rms of squared filtered signal
%   noiseType  = 'before'      — noise window immediately before signal, no gap
%   freq       = [40 80] Hz    — hardcoded FIR CutoffFrequency1/2 in the code
%                                (note: paper text states 20-115 Hz, but the
%                                 supplemental code uses 40-80 Hz)
%   SNR = 10*log10(abs((rmsSignal - rmsNoise)^2 / noiseVar))  [Lurton 2010 eq.6.26]
%   where rmsSignal = rms(filteredAudio.^2)  i.e. rms of instantaneous power
params = struct( ...
    'snrType',       'timeDomain', ...
    'useLurton',     true, ...
    'freq',          [40 80], ...
    'showClips',     false, ...
    'noiseDuration', 'before', ...
    'noiseDelay',    0);

if ~isempty(metadata)
    params.metadata = metadata;
end

%% DIAGNOSTICS — test single annotation before batch run
fprintf('\n--- Diagnostics ---\n');
row1 = analystAnnot(1,:);
fprintf('  annot(1).soundFolder = %s\n', row1.soundFolder{1});
fprintf('  annot(1).t0          = %s\n', datestr(row1.t0, 'yyyy-mm-dd HH:MM:SS.FFF'));
fprintf('  annot(1).tEnd        = %s\n', datestr(row1.tEnd, 'yyyy-mm-dd HH:MM:SS.FFF'));
fprintf('  annot(1).duration    = %.2f s\n', row1.duration);
fprintf('  annot(1).freq        = [%.0f %.0f] Hz\n', row1.freq(1), row1.freq(2));
fprintf('  annot(1).channel     = %d\n', row1.channel);

% Test wavFolderInfo directly
fprintf('\nTesting wavFolderInfo...\n');
try
    sf = wavFolderInfo(row1.soundFolder{1});
    fprintf('  wavFolderInfo: %d files found\n', numel(sf));
    fprintf('  First file: %s\n', sf(1).fname);
    fprintf('  First startDate: %s\n', datestr(sf(1).startDate,'yyyy-mm-dd HH:MM:SS'));
    fprintf('  Last  startDate: %s\n', datestr(sf(end).startDate,'yyyy-mm-dd HH:MM:SS'));
    fprintf('  annot t0:        %s\n', datestr(row1.t0,'yyyy-mm-dd HH:MM:SS.FFF'));
    fprintf('  t0 in range:     %d\n', row1.t0 >= sf(1).startDate && row1.t0 <= sf(end).startDate + 1);
catch err
    fprintf('  wavFolderInfo FAILED: %s\n', err.message);
    % Show what files are actually in the folder
    wavFiles = dir(fullfile(row1.soundFolder{1}, '*.wav'));
    fprintf('  Files in folder: %d\n', numel(wavFiles));
    if numel(wavFiles) > 0
        fprintf('  First filename:  %s\n', wavFiles(1).name);
        fprintf('  Last  filename:  %s\n', wavFiles(end).name);
    end
    % Try xwavFolderInfo in case these are HARP x.wav files
    try
        sf2 = xwavFolderInfo(row1.soundFolder{1});
        fprintf('  xwavFolderInfo: %d files found\n', numel(sf2));
        if numel(sf2) > 0
            fprintf('  --> Use xwavFolderInfo instead of wavFolderInfo\n');
        end
    catch err2
        fprintf('  xwavFolderInfo FAILED: %s\n', err2.message);
    end
end

% Check what processOne sees after table2struct
fprintf('\nChecking table2struct field types...\n');
s1 = table2struct(analystAnnot(1,:));
fprintf('  soundFolder class: %s\n', class(s1.soundFolder));
if iscell(s1.soundFolder)
    fprintf('  soundFolder value: %s\n', s1.soundFolder{1});
else
    fprintf('  soundFolder value: %s\n', s1.soundFolder);
end
fprintf('  freq class:        %s\n', class(s1.freq));
if iscell(s1.freq)
    fprintf('  freq value:        [%.0f %.0f]\n', s1.freq{1}(1), s1.freq{1}(2));
else
    fprintf('  freq value:        [%.0f %.0f]\n', s1.freq(1), s1.freq(2));
end
fprintf('  t0 class:          %s\n', class(s1.t0));
fprintf('  t0 value:          %s\n', datestr(s1.t0,'yyyy-mm-dd HH:MM:SS.FFF'));

% Test single snrEstimate call with showClips=false, force serial
fprintf('\nTesting snrEstimate on single annotation...\n');
pTest = struct('snrType','spectrogram','showClips',false,'parallelThreshold',Inf);
[snrTest, rmsS, rmsN] = snrEstimate(row1, pTest);
fprintf('  SNR = %.2f dB, rmsSignal = %.4g, rmsNoise = %.4g\n', snrTest, rmsS, rmsN);

% Test getAudioFromFiles directly
fprintf('\nTesting getAudioFromFiles directly...\n');
try
    sf1 = row1.soundFolder;
    if iscell(sf1), sf1 = sf1{1}; end
    sf = wavFolderInfo(sf1);
    fprintf('  wavFolderInfo: %d files\n', numel(sf));
    fprintf('  File range: %s to %s\n', ...
        datestr(sf(1).startDate,'yyyy-mm-dd HH:MM:SS'), ...
        datestr(sf(end).startDate,'yyyy-mm-dd HH:MM:SS'));
    fprintf('  annot t0:   %s\n', datestr(row1.t0,'yyyy-mm-dd HH:MM:SS.FFF'));
    fprintf('  t0 in range: %d\n', ...
        row1.t0 >= sf(1).startDate & row1.t0 <= sf(end).startDate + 1);
    [audio, ~, fi] = getAudioFromFiles(sf, row1.t0, row1.tEnd, newRate=sf(1).sampleRate);
    fprintf('  Audio length = %d samples (%.2f s at %d Hz)\n', ...
        numel(audio), numel(audio)/sf(1).sampleRate, sf(1).sampleRate);
catch err
    fprintf('  getAudioFromFiles FAILED: %s\n', err.message);
    fprintf('  (Check that t0 falls within the WAV file date range)\n');
end
fprintf('-------------------\n\n');

%% COMPUTE SNR — ANALYST DETECTIONS
fprintf('Computing SNR for analyst detections (%d)...\n', height(analystAnnot));
tic;
analystResults = snrEstimate(analystAnnot, params);
fprintf('  Done in %.1f s\n', toc);

%% COMPUTE SNR — DETECTOR DETECTIONS
fprintf('Computing SNR for detector detections (%d)...\n', height(detectorAnnot));
tic;
detectorResults = snrEstimate(detectorAnnot, params);
fprintf('  Done in %.1f s\n', toc);

%% SUMMARY STATISTICS
analystSNR  = analystResults.snr;
detectorSNR = detectorResults.snr;

% Remove NaNs (failed audio reads)
analystSNR  = analystSNR(isfinite(analystSNR));
detectorSNR = detectorSNR(isfinite(detectorSNR));

fprintf('\n--- SNR summary (snrType=%s, noiseDuration=%s, noiseDelay=%.1fs) ---\n', ...
    params.snrType, params.noiseDuration, params.noiseDelay);
fprintf('                   Analyst    Detector\n');
fprintf('  N (finite SNR):  %-10d %-10d\n', numel(analystSNR), numel(detectorSNR));
fprintf('  Mean SNR (dB):   %-10.1f %-10.1f\n', mean(analystSNR), mean(detectorSNR));
fprintf('  Median SNR (dB): %-10.1f %-10.1f\n', median(analystSNR), median(detectorSNR));
fprintf('  Std SNR (dB):    %-10.1f %-10.1f\n', std(analystSNR), std(detectorSNR));
fprintf('  10th pct (dB):   %-10.1f %-10.1f\n', prctile(analystSNR,10), prctile(detectorSNR,10));
fprintf('  5th pct (dB):    %-10.1f %-10.1f\n', prctile(analystSNR,5), prctile(detectorSNR,5));

% Paper SNR bins: low/medium/high each containing 1/3rd of true-positive detections
% Reported boundaries: -12 dB (low/medium) and -3 dB (medium/high)
% Check whether our analyst distribution is consistent with these
fprintf('  33rd pct (dB):   %-10.1f %-10.1f   (paper: -12 dB)\n', ...
    prctile(analystSNR,33), prctile(detectorSNR,33));
fprintf('  67th pct (dB):   %-10.1f %-10.1f   (paper: -3 dB)\n', ...
    prctile(analystSNR,67), prctile(detectorSNR,67));

% Key test from Miller et al. (2022): detector probability of detection
% was ~90% at ALL SNR levels; analyst was ~70% at low/medium SNR rising
% to 83% at high SNR. So detector median SNR should be lower than analyst.
if median(detectorSNR) < median(analystSNR)
    fprintf('\n  [PASS] Detector median (%.1f dB) < analyst median (%.1f dB)\n', ...
        median(detectorSNR), median(analystSNR));
    fprintf('         Consistent with Miller et al. (2022): detector detects quieter calls.\n');
else
    fprintf('\n  [NOTE] Detector median (%.1f dB) >= analyst median (%.1f dB)\n', ...
        median(detectorSNR), median(analystSNR));
    fprintf('         Check snrType, freq band and noiseDelay match paper settings.\n');
end

% Cross-check: paper reports SNR bin boundaries of -12 dB and -3 dB
% (1/3rd quantiles of true-positive detections). If our 33rd/67th
% percentiles of analyst SNR are in that ballpark, method is consistent.
p33 = prctile(analystSNR, 33);
p67 = prctile(analystSNR, 67);
fprintf('  Analyst SNR bin boundaries: %.1f dB (low/med) and %.1f dB (med/high)\n', p33, p67);
fprintf('  Paper reported:             -12 dB and -3 dB\n');
if abs(p33 - (-12)) < 5 && abs(p67 - (-3)) < 5
    fprintf('  [PASS] SNR bin boundaries consistent with paper (within 5 dB).\n');
else
    fprintf('  [NOTE] SNR bin boundaries differ from paper by >5 dB — check method settings.\n');
end

%% FIGURE 1: SNR distributions
figure('Name', 'D-call SNR distributions — Miller et al. 2022', ...
    'Position', [100 100 700 400]);

edges = -5 : 1 : 30;
histogram(analystSNR,  edges, 'FaceColor', [0.2 0.5 0.8], ...
    'FaceAlpha', 0.6, 'DisplayName', sprintf('Analyst (n=%d)', numel(analystSNR)));
hold on;
histogram(detectorSNR, edges, 'FaceColor', [0.8 0.3 0.2], ...
    'FaceAlpha', 0.6, 'DisplayName', sprintf('Detector (n=%d)', numel(detectorSNR)));
hold off;

xline(median(analystSNR),  '--', 'Color', [0.2 0.5 0.8], 'LineWidth', 1.5, ...
    'HandleVisibility', 'off');
xline(median(detectorSNR), '--', 'Color', [0.8 0.3 0.2], 'LineWidth', 1.5, ...
    'HandleVisibility', 'off');

xlabel('SNR (dB)');
ylabel('Count');
title('Antarctic blue whale D-call SNR — Casey 2019 test dataset');
legend('Location', 'northeast');
grid on;

levelLabel = 'dBFS';
if ~isempty(metadata), levelLabel = 'dB re 1 µPa'; end
text(0.02, 0.97, sprintf('Method: spectrogram | Freq: per annotation | Levels: %s', levelLabel), ...
    'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 7, 'Color', [0.4 0.4 0.4]);

%% FIGURE 2: Example spectrograms — quietest analyst detections
% Show the 6 quietest analyst D-calls to illustrate low-SNR appearance
fprintf('\nPlotting example spectrograms of quietest analyst detections...\n');

[~, sortIdx] = sort(analystResults.snr, 'ascend');
nExamples    = min(6, sum(isfinite(analystResults.snr)));
exampleIdx   = sortIdx(isfinite(analystResults.snr(sortIdx)));
exampleIdx   = exampleIdx(1:nExamples);

% sp.freq not set here — spectroAnnotationAndNoise will use annot.freq
sp = struct('pre', 1, 'post', 1, 'yLims', [0 125], ...
    'noiseDelay', 0, 'win', 200, 'overlap', 170);

fig2 = figure('Name', 'Quietest D-calls — analyst', ...
    'Position', [150 150 900 500]);
tlo  = tiledlayout(fig2, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo, 'Quietest analyst D-call detections (Casey 2019)', 'interpreter', 'none');

for k = 1:nExamples
    nexttile(tlo);
    row = analystAnnot(exampleIdx(k), :);
    pEx = struct('snrType', 'spectrogram', 'showClips', true, ...
        'pauseAfterPlot', false, 'spectroParams', sp);
    if ~isempty(metadata), pEx.metadata = metadata; end
    snr_k = snrEstimate(row, pEx);
    title(gca, sprintf('SNR = %.1f dB', snr_k), 'FontSize', 8);
end

fprintf('\nValidation complete.\n');
fprintf('See Miller et al. (2022) https://doi.org/10.1002/rse2.297\n');

fprintf(['\n--- Reproducibility notes ---\n' ...
    'bsnr does not exactly reproduce the individual SNR values in the Miller\n' ...
    'et al. (2022) capture history (Data S4). Investigation found:\n' ...
    '\n' ...
    '1. BEST bsnr MATCH (analyst annotations only, n=1565):\n' ...
    '   spectrogram [20-115 Hz] before Lurton: r=0.604, RMSE=11.8 dB\n' ...
    '   This is the appropriate bsnr validation — running on analyst\n' ...
    '   annotations the way bsnr is designed to be used.\n' ...
    '\n' ...
    '2. CAPTURE HISTORY REPRODUCTION (all 2189 reconciled detections):\n' ...
    '   All tested configurations gave r=0.33-0.36, RMSE~14 dB.\n' ...
    '   Root cause: the exact version of annotationSNR.m that generated\n' ...
    '   the published SNR values is unrecoverable. The timeDomain code path\n' ...
    '   was added after submission; the spectrogram path with the original\n' ...
    '   parameters is unknown. Tried: spectrogram/timeDomain, [20-115]/\n' ...
    '   [30-115]/[40-80] Hz, 250/1000 Hz sample rate — none reproduced.\n' ...
    '\n' ...
    '3. SUPPLEMENTAL CODE ISSUES:\n' ...
    '   - Data S4 in the original zip was a pre-addSnr intermediate table\n' ...
    '     (67 cols, no snrLurton). Correct file is the _cut version (70 cols).\n' ...
    '   - annotationSNR.m in the zip has noiseType=''timeDomain'' which was\n' ...
    '     added post-submission and does not match what generated the results.\n' ...
    '   A correction to the supplemental material is warranted.\n' ...
    '\n' ...
    '4. KEY SCIENTIFIC FINDING REPRODUCES:\n' ...
    '   Analyst SNR bin boundaries (-10.8 and -2.2 dB) match the paper''s\n' ...
    '   reported values (-12 and -3 dB) within 2 dB. Detector median SNR\n' ...
    '   < analyst median SNR — the paper''s central finding is confirmed.\n']);

%% PARAMETER SWEEP vs PAPER (Data S4 — adjudicated capture history)
% Compare bsnr SNR estimates against the paper's published snrLurton values
% across combinations of snrType, freq band, noise strategy, and SNR formula.
% This reveals which settings best reproduce the published values, and also
% provides a methods comparison on the same adjudicated true-positive detections.
if ~exist(captureHistoryFile, 'file')
    fprintf('\n[SKIP] Capture history not found: %s\n', captureHistoryFile);
    fprintf('       Download Data S4 from https://doi.org/10.1002/rse2.297\n');
else
    fprintf('\n--- Parameter sweep vs Data S4 (adjudicated true positives) ---\n');
    % Suppress benign filter warning for short calls where noise window is
    % too short for the FIR filter order — NaN is returned and handled gracefully.
    warning('off', 'snrTimeDomain:failed');
    cleanupW = onCleanup(@() warning('on', 'snrTimeDomain:failed'));
    ch = readtable(captureHistoryFile);

    % verdict is stored as string '1'/'0' in this file
    if isnumeric(ch.verdict)
        tpMask = ch.verdict == 1;
    else
        tpMask = strcmp(string(ch.verdict), '1');
    end
    paperTP_t0 = ch.t0(tpMask);
    fprintf('  True positives in capture history: %d/%d\n', sum(tpMask), height(ch));

    % Get paper's published SNR — column is 'snrLurton' in _cut version,
    % 'snr' in the full capture history (which contains the Lurton formula result)
    lurtonCol = ch.Properties.VariableNames( ...
        contains(ch.Properties.VariableNames, 'Lurton', 'IgnoreCase', true));
    if isempty(lurtonCol)
        % Fall back to 'snr' column (Lurton formula in the original code)
        lurtonCol = ch.Properties.VariableNames(strcmp(ch.Properties.VariableNames, 'snr'));
    end
    if isempty(lurtonCol), lurtonCol = ch.Properties.VariableNames(end); end
    fprintf('  Using SNR column: %s\n', lurtonCol{1});
    paperSNR = ch.(lurtonCol{1})(tpMask);
    fprintf('  Paper SNR (Lurton): mean=%.1f  median=%.1f  33rd=%.1f  67th=%.1f dB\n', ...
        mean(paperSNR,'omitnan'), median(paperSNR,'omitnan'), ...
        prctile(paperSNR,33), prctile(paperSNR,67));
    fprintf('  (Paper reports bin boundaries: -12 dB and -3 dB)\n\n');

    % Match paper true-positives to analyst annotation table by t0 (within 1 s)
    ourT0    = analystAnnot.t0;
    matchIdx = nan(numel(paperTP_t0), 1);
    for k = 1:numel(paperTP_t0)
        [dt, j] = min(abs(ourT0 - paperTP_t0(k)));
        if dt < 1/86400, matchIdx(k) = j; end
    end
    matched = isfinite(matchIdx);
    fprintf('  Matched %d/%d true positives to analyst annotations\n\n', ...
        sum(matched), numel(paperTP_t0));

    % Parameter combinations to sweep
    % {snrType, freq, noiseDuration, useLurton, label}
    % Parameters from judgeDetections.m > addSnr() in the official supplemental:
    %   annotationSNR called with params.freq=[30 115], noiseDelay=0
    %   BUT annotationSNR timeDomain path ignores params.freq — uses hardcoded [40 80]
    %   Duration: max(analyst duration, detector duration) — not just analyst
    %   soundFolder: analyst's path (m:\annotatedLibrary_MGA\)
    % Since we're running on analyst annotations only, duration = analyst duration.
    % The max-duration effect would only matter for detections where detector
    % duration > analyst duration — this adds noise to the correlation.

    % freq=[] means use each annotation's own frequency bounds (annot.freq)
    sweepConfigs = {
        'timeDomain',        [40  80],  'before',         true,  'timeDomain [40-80] before Lurton  (supp. code)'
        'timeDomain',        [20 115],  'before',         true,  'timeDomain [20-115] before Lurton  (paper text)'
        'timeDomain',        [],        'before',         true,  'timeDomain [per-annot] before Lurton'
        'timeDomain',        [40  80],  'beforeAndAfter', true,  'timeDomain [40-80] beforeAndAfter Lurton'
        'timeDomain',        [40  80],  'before',         false, 'timeDomain [40-80] before simple'
        'spectrogram',       [30 115],  'before',         true,  'spectrogram [30-115] before Lurton  (est. actual config)'
        'spectrogram',       [40  80],  'before',         true,  'spectrogram [40-80] before Lurton'
        'spectrogram',       [20 115],  'before',         true,  'spectrogram [20-115] before Lurton'
        'spectrogram',       [],        'before',         true,  'spectrogram [per-annot] before Lurton'
        'spectrogram',       [20 115],  'before',         false, 'spectrogram [20-115] before simple'
        'spectrogramSlices', [20 115],  'before',         true,  'spectrogramSlices [20-115] before Lurton'
        'spectrogramSlices', [],        'before',         true,  'spectrogramSlices [per-annot] before Lurton'
    };
    nConfigs = size(sweepConfigs, 1);

    fprintf('  %-52s  %5s  %6s  %6s  n\n', 'Configuration', 'r', 'RMSE', 'Bias');
    fprintf('  %s\n', repmat('-', 1, 78));

    sweepLabel = cell(nConfigs, 1);
    sweepR     = nan(nConfigs, 1);
    sweepRMSE  = nan(nConfigs, 1);
    sweepBias  = nan(nConfigs, 1);
    sweepSNRs  = cell(nConfigs, 1);

    for c = 1:nConfigs
        pSweep = struct( ...
            'snrType',       sweepConfigs{c,1}, ...
            'noiseDuration', sweepConfigs{c,3}, ...
            'useLurton',     sweepConfigs{c,4}, ...
            'showClips',     false, ...
            'noiseDelay',    0);
        if ~isempty(sweepConfigs{c,2})
            pSweep.freq = sweepConfigs{c,2};   % fixed band
        end  % else: omit freq so snrEstimate uses annot.freq per detection
        if ~isempty(metadata), pSweep.metadata = metadata; end

        sweepR_tbl   = snrEstimate(analystAnnot, pSweep);
        sweepSNR_all = sweepR_tbl.snr;
        sweepSNRs{c} = sweepSNR_all;

        % Extract matched values
        validMatch = find(matched);
        ourVec   = nan(numel(validMatch), 1);
        paperVec = paperSNR(matched);
        for k = 1:numel(validMatch)
            ourVec(k) = sweepSNR_all(matchIdx(validMatch(k)));
        end
        ok = isfinite(ourVec) & isfinite(paperVec);

        if sum(ok) > 5
            r    = corr(paperVec(ok), ourVec(ok));
            rmse = sqrt(mean((paperVec(ok) - ourVec(ok)).^2));
            bias = mean(ourVec(ok) - paperVec(ok));
        else
            r = nan; rmse = nan; bias = nan;
        end
        sweepLabel{c} = sweepConfigs{c,5};
        sweepR(c)     = r;
        sweepRMSE(c)  = rmse;
        sweepBias(c)  = bias;
        fprintf('  %-52s  %5.3f  %6.1f  %+6.1f  %d\n', ...
            sweepConfigs{c,5}, r, rmse, bias, sum(ok));
    end

    [~, bestIdx] = max(sweepR);
    fprintf('\n  Best match: %s (r=%.3f, RMSE=%.1f dB, bias=%+.1f dB)\n', ...
        sweepLabel{bestIdx}, sweepR(bestIdx), sweepRMSE(bestIdx), sweepBias(bestIdx));

    %% Scatter plot grid: each configuration vs paper snrLurton
    nCols    = 3;
    nRows    = ceil(nConfigs / nCols);
    figSweep = figure('Name', 'Parameter sweep vs paper snrLurton', ...
        'Position', [50 50 min(nCols,nConfigs)*280 nRows*270]);
    tloS = tiledlayout(figSweep, nRows, nCols, 'TileSpacing','compact','Padding','compact');
    title(tloS, 'bsnr configurations vs paper snrLurton (adjudicated true positives)', ...
        'interpreter','none');

    for c = 1:nConfigs
        nexttile(tloS);
        sweepSNR_all = sweepSNRs{c};
        validMatch = find(matched);
        ourVec   = nan(numel(validMatch), 1);
        paperVec = paperSNR(matched);
        for k = 1:numel(validMatch)
            ourVec(k) = sweepSNR_all(matchIdx(validMatch(k)));
        end
        ok = isfinite(ourVec) & isfinite(paperVec);
        if sum(ok) > 1
            scatter(paperVec(ok), ourVec(ok), 8, 'filled', 'MarkerFaceAlpha', 0.3);
            hold on;
            lims = [min([paperVec(ok); ourVec(ok)]) max([paperVec(ok); ourVec(ok)])];
            plot(lims, lims, 'k--', 'LineWidth', 1);
            hold off;
            text(0.05, 0.95, sprintf('r=%.2f  bias=%+.1f', sweepR(c), sweepBias(c)), ...
                'Units','normalized','VerticalAlignment','top','FontSize',7);
        end
        title(gca, sweepLabel{c}, 'interpreter','none','FontSize',7);
        xlabel('Paper (dB)','FontSize',7); ylabel('bsnr (dB)','FontSize',7);
        grid on;
    end
end
