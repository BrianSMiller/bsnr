function test_plots()
% Visual inspection tests for snrEstimate plotting output.
%
% Produces one figure per SNR method, each showing a 1x5 grid of test
% signals (columns): noise only | moderate SNR | high SNR | SRW upcall |
% bioduck bout
%
% This layout allows methods to be compared by placing figures side by
% side, and signals to be compared by reading across the row.
%
% Methods shown:
%   Figure 1  spectrogram
%   Figure 2  spectrogramSlices
%   Figure 3  timeDomain          (power time series, all five signals)
%   Figure 4  ridge
%   Figure 5  synchrosqueeze
%   Figure 6  quantiles           (with 85th/15th percentile contours)
%   Figure 7  spectrogram+Lurton
%   Figure 8  nist                (histogram method)
%
% Figures are left open for inspection. Close all with: close all

fprintf('\n=== test_plots ===\n');
fprintf('Figures will remain open for inspection. Close with: close all\n\n');

close all;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Shared fixture parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sampleRate  = 2000;
toneFreq    = [150 250];

sp.pre        = 1;
sp.post       = 1;
sp.yLims      = [0 300];
sp.freq       = toneFreq;
sp.win        = floor(sampleRate / 4);
sp.overlap    = floor(sp.win * 0.75);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Build tone fixtures (shared across method figures)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('Building tone fixtures...\n');
sigConfigs = {
    'Noise only',      0.0,  0.1
    'Moderate (~6 dB)', 0.2,  0.1
    'High SNR (~20 dB)', 1.0,  0.1
};
nTone = size(sigConfigs, 1);
toneAnnots   = cell(nTone, 1);
toneCleanups = cell(nTone, 1);

for s = 1:nTone
    [toneAnnots{s}, toneCleanups{s}] = createTestFixture( ...
        'signalRMS', sigConfigs{s,2}, 'noiseRMS', sigConfigs{s,3}, ...
        'toneFreqHz', 200, 'freq', toneFreq, 'durationSec', 4, ...
        'classification', sigConfigs{s,1});
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Build SRW upcall fixture
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('Building SRW upcall fixture...\n');
srwRate     = 1000;
srwNoiseRMS = 0.1;
srwFreq     = [75 210];
bufferSec   = 3;

[srwSig, ~] = makeSRWUpcall(srwRate, srwNoiseRMS);
rng(7);
srwWideRMS  = srwNoiseRMS * sqrt(srwRate/2 / diff(srwFreq));
bufSamps    = round(bufferSec * srwRate);
fullAudio   = [srwWideRMS*randn(bufSamps,1); srwSig; srwWideRMS*randn(bufSamps,1)];
fullAudio   = fullAudio * (0.9/max(abs(fullAudio)));

srwDir = fullfile(tempdir, sprintf('bsnr_plots_srw_%s', datestr(now,'yyyymmdd_HHMMSS_FFF')));
mkdir(srwDir);
srwStart = floor(now()*86400)/86400;
audiowrite(fullfile(srwDir, [datestr(srwStart,'yyyy-mm-dd_HH-MM-SS') '.wav']), fullAudio, srwRate);
srwCleanup = @() rmdir(srwDir,'s');

srwAnnot.soundFolder    = srwDir;
srwAnnot.t0             = srwStart + bufferSec/86400;
srwAnnot.tEnd           = srwStart + (bufferSec+1.0)/86400;
srwAnnot.duration       = 1.0;
srwAnnot.freq           = srwFreq;
srwAnnot.channel        = 1;
srwAnnot.classification = 'SRW upcall f(t)=80+118t^2 Hz';

srwSP           = sp;
srwSP.yLims   = [0 300];
srwSP.freq      = srwFreq;
srwSP.win       = floor(srwRate/4);
srwSP.overlap   = floor(srwSP.win * 0.9);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Build bioduck fixture (20s bout of repeated FM downsweeps, 60-100 Hz)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('Building bioduck fixture...\n');
% Bioduck spectro params from spectroParams('bioduck'):
% sampleRate=1000, nfft=256, noverlap=224 (87.5%%), freq=30-500 Hz, pre/post=1s
bdRate  = 1000;
bdFreq  = [30 500];
bdDur   = 10;    % ~2 series — mimics Dominello & Sirovic 2016 Fig 2a

[bdAnnot, bdCleanup] = createTestFixture( ...
    'signalType',  'bioduck', ...
    'sampleRate',  bdRate, ...
    'durationSec', bdDur, ...
    'signalRMS',   1.0, ...
    'noiseRMS',    0.1, ...
    'classification', 'AMW bioduck A1: 4x(200->60Hz/0.1s) @ 0.3s IPI, 3.1s ISI');

bdSP          = sp;
bdSP.yLims    = [0 300];
bdSP.freq     = bdFreq;
bdSP.pre      = 1;
bdSP.post     = 1;
bdSP.win      = 256;
bdSP.overlap  = 224;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Assemble signal list
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

colLabels = [sigConfigs(:,1); {'SRW upcall'}; {'Bioduck bout'}];
allAnnots = [toneAnnots; {srwAnnot}; {bdAnnot}];
allSP     = [repmat({sp}, nTone, 1); {srwSP}; {bdSP}];
nCols     = numel(colLabels);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Helper: draw one method figure (1 x nCols grid)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

figW   = 300 * nCols;
figH   = 350;
figPos = [50 50 figW figH];

nMethods = 8;
snrTable = nan(nMethods, nCols);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 1: spectrogram
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 1: spectrogram ---\n');
fig1 = figure('Name','spectrogram','Position',figPos);
tlo1 = tiledlayout(fig1,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo1,'spectrogram','interpreter','none');
for s = 1:nCols
    nexttile(tlo1);
    p = struct('snrType','spectrogram','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(1,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 1 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 2: spectrogramSlices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 2: spectrogramSlices ---\n');
fig2 = figure('Name','spectrogramSlices','Position',figPos);
tlo2 = tiledlayout(fig2,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo2,'spectrogramSlices','interpreter','none');
for s = 1:nCols
    nexttile(tlo2);
    p = struct('snrType','spectrogramSlices','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(2,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 2 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 3: timeDomain (power time series for all signals)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 3: timeDomain ---\n');
fig3 = figure('Name','timeDomain','Position',figPos);
tlo3 = tiledlayout(fig3,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo3,'timeDomain','interpreter','none');
for s = 1:nCols
    nexttile(tlo3);
    p = struct('snrType','timeDomain','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(3,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 3 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 4: ridge
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 4: ridge ---\n');
fig4 = figure('Name','ridge','Position',figPos);
tlo4 = tiledlayout(fig4,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo4,'ridge','interpreter','none');
for s = 1:nCols
    nexttile(tlo4);
    p = struct('snrType','ridge','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(4,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 4 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 5: synchrosqueeze
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 5: synchrosqueeze ---\n');
fig5 = figure('Name','synchrosqueeze','Position',figPos);
tlo5 = tiledlayout(fig5,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo5,'synchrosqueeze','interpreter','none');
for s = 1:nCols
    nexttile(tlo5);
    p = struct('snrType','synchrosqueeze','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(5,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 5 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 6: quantiles (with percentile contour overlay)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 6: quantiles ---\n');
fig6 = figure('Name','quantiles','Position',figPos);
tlo6 = tiledlayout(fig6,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo6,'quantiles (p=0.85/0.15 contours)','interpreter','none');
for s = 1:nCols
    nexttile(tlo6);
    p = struct('snrType','quantiles','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(6,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 6 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 7: spectrogram + Lurton
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 7: spectrogram (Lurton) ---\n');
fig7 = figure('Name','spectrogram-Lurton','Position',figPos);
tlo7 = tiledlayout(fig7,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo7,'spectrogram (Lurton formula)','interpreter','none');
for s = 1:nCols
    nexttile(tlo7);
    p = struct('snrType','spectrogram','useLurton',true,'showClips',true,...
        'pauseAfterPlot',false,'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(7,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 7 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Figure 8: NIST histogram method
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Figure 8: nist (histogram) ---\n');
fig8 = figure('Name','nist-histogram','Position',figPos);
tlo8 = tiledlayout(fig8,1,nCols,'TileSpacing','compact','Padding','compact');
title(tlo8,'nist (frame energy histogram)','interpreter','none');
for s = 1:nCols
    nexttile(tlo8);
    p = struct('snrType','nist','showClips',true,'pauseAfterPlot',false,...
        'spectroParams',allSP{s});
    snr = snrEstimate(allAnnots{s}, p);
    snrTable(8,s) = snr;
    title(gca, sprintf('%s | %.1f dB', colLabels{s}, snr), 'interpreter','none','FontSize',8);
    fprintf('  %s: SNR=%.2f dB\n', colLabels{s}, snr);
end
fprintf('  [PASS] Figure 8 complete\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Cleanup and summary
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for s = 1:nTone, toneCleanups{s}(); end
srwCleanup();
bdCleanup();

methodNames = {'spectrogram','spectrogramSlices','timeDomain','ridge',...
               'synchrosqueeze','quantiles','spectrogram(Lurton)','nist'};
sigNames    = strrep(colLabels, ' ', '_');
sigNames    = strrep(sigNames, '(', '');
sigNames    = strrep(sigNames, ')', '');
sigNames    = strrep(sigNames, '~', '');
sigNames    = strrep(sigNames, '%', '');

snrResults = array2table(snrTable, ...
    'RowNames', methodNames, 'VariableNames', sigNames);
fprintf('\n--- SNR summary (dB, simple formula) ---\n');
disp(snrResults);

fprintf('\n=== test_plots PASSED ===\n');
fprintf('(%d figures open for inspection)\n', numel(findobj('type','figure')));
end
