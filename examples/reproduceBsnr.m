%% reproduceBsnr.m
% Attempt to reproduce the SNR values in the Miller et al. (2022) capture
% history (Data S4) using bsnr across a full combinatorial sweep.
%
% Results are cached to a .mat file shared with reproduceFromSuppMatt.m.
% Set overwriteCache=true to recompute.
%
% Brian Miller, Australian Antarctic Division. Added post-publication.

%% Settings
overwriteCache     = false;
cacheFile          = 'reproduceCapHist_cache.mat';

%% Paths — edit these to match your local setup
captureHistoryFile = 'C:\analysis\bsnr\examples\S4-captureHistory_casey2019MGA_vs_denseNetBmD24_judgedBSM_cut.csv';
soundFolder        = 'w:\annotatedLibrary\BAFAAL\casey2019\wav\';
bsnrFolder         = 'C:\analysis\bsnr';

%% Path setup — bsnr and dependencies only
restoredefaultpath;
addpath(bsnrFolder, '-begin');
addpath(fullfile(bsnrFolder,'..','soundFolder'), '-begin');
addpath(fullfile(bsnrFolder,'..','annotatedLibrary'), '-begin');
addpath(fullfile(bsnrFolder,'..','longTermRecorders'), '-begin');
fprintf('  which snrEstimate:       %s\n', which('snrEstimate'));
fprintf('  which wavFolderInfo:     %s\n', which('wavFolderInfo'));
fprintf('  which getAudioFromFiles: %s\n\n', which('getAudioFromFiles'));

%% Load cache
if exist(cacheFile,'file') && ~overwriteCache
    load(cacheFile,'cache');
    fprintf('Loaded %d cached configurations from %s\n', numel(cache), cacheFile);
else
    cache = struct('label',{},'params',{},'softwareVersion',{}, ...
        'snrVec',{},'r',{},'rmse',{},'bias',{},'n',{},'runDate',{});
end

%% Load capture history
[paperSNR, tpMask, annot] = loadCaptureHistory(captureHistoryFile, soundFolder);

%% Parameter combinations
freqBands     = {[20 115], [30 115], [40 80], [30 60]};
freqLabels    = {'[20-115]', '[30-115]', '[40-80]', '[30-60]'};
snrTypes      = {'spectrogram', 'spectrogramSlices', 'timeDomain'};
useLurtons    = {true, false};
resampleRates = {[], 250};
noiseDurs     = {'before', 'beforeAndAfter'};

nTotal = numel(snrTypes)*numel(freqBands)*numel(useLurtons)* ...
         numel(resampleRates)*numel(noiseDurs);
fprintf('Running %d bsnr configurations...\n\n', nTotal);
fprintf('  %-62s  %5s  %6s  %6s  %4s\n', 'Configuration','r','RMSE','Bias','n');
fprintf('  %s\n', repmat('-',1,84));

warning('off','snrTimeDomain:failed');
cleanupW = onCleanup(@() warning('on','snrTimeDomain:failed'));

bsnrVer = struct( ...
    'snrEstimate',       getFuncVersion('snrEstimate'), ...
    'wavFolderInfo',     getFuncVersion('wavFolderInfo'), ...
    'getAudioFromFiles', getFuncVersion('getAudioFromFiles'), ...
    'matlabVersion',     version());

for si = 1:numel(snrTypes)
for fi = 1:numel(freqBands)
for li = 1:numel(useLurtons)
for ri = 1:numel(resampleRates)
for ni = 1:numel(noiseDurs)
    rateStr   = ''; if ~isempty(resampleRates{ri}), rateStr = sprintf(' %dHz',resampleRates{ri}); end
    lurtonStr = 'simple'; if useLurtons{li}, lurtonStr = 'Lurton'; end
    label = sprintf('bsnr %s %s %s %s%s', ...
        snrTypes{si}, freqLabels{fi}, noiseDurs{ni}, lurtonStr, rateStr);

    cIdx = findInCache(cache, label);
    if cIdx > 0 && ~overwriteCache
        printRow(label, cache(cIdx).r, cache(cIdx).rmse, ...
            cache(cIdx).bias, cache(cIdx).n);
        continue;
    end

    p = struct('snrType',snrTypes{si},'freq',freqBands{fi}, ...
        'noiseDuration',noiseDurs{ni},'useLurton',useLurtons{li}, ...
        'showClips',false,'noiseDelay',0);
    if ~isempty(resampleRates{ri}), p.resampleRate = resampleRates{ri}; end

    result = snrEstimate(annot, p);
    [r,rmse,bias,n] = getStats(paperSNR, result.snr, tpMask);
    printRow(label, r, rmse, bias, n);

    entry = makeEntry(label, p, result.snr, r, rmse, bias, n, bsnrVer);
    cache = updateCache(cache, cIdx, entry);
    save(cacheFile,'cache');
end
end
end
end
end

printSummary(cache);
fprintf('\nCache saved to: %s\n', fullfile(pwd,cacheFile));

%% Local helper functions

function [paperSNR, tpMask, annot, c] = loadCaptureHistory(captureHistoryFile, soundFolder)
    fprintf('Loading capture history...\n');
    c = readtable(captureHistoryFile);
    fprintf('  %d rows, %d columns\n', height(c), width(c));
    if isnumeric(c.verdict)
        tpMask = c.verdict == 1;
    else
        tpMask = strcmp(string(c.verdict), '1');
    end
    fprintf('  True positives: %d/%d\n', sum(tpMask), height(c));
    lurtonCol = c.Properties.VariableNames( ...
        contains(c.Properties.VariableNames, 'Lurton', 'IgnoreCase', true));
    snrCol = 'snr';
    if ~isempty(lurtonCol), snrCol = lurtonCol{1}; end
    fprintf('  Reference SNR column: %s\n\n', snrCol);
    paperSNR = c.(snrCol);
    annot = table();
    annot.t0          = c.t0;
    annot.tEnd        = c.t0 + c.duration/86400;
    annot.duration    = c.duration;
    annot.freq        = [c.freq_1, c.freq_2];
    annot.soundFolder = repmat({soundFolder}, height(c), 1);
    annot.channel     = ones(height(c), 1);
    c.soundFolder     = annot.soundFolder;
end

function [r, rmse, bias, n] = getStats(paperSNR, recompSNR, tpMask)
    ok = isfinite(paperSNR) & isfinite(recompSNR) & tpMask;
    n = sum(ok);
    if n < 5, r = nan; rmse = nan; bias = nan; return; end
    r    = corr(paperSNR(ok), recompSNR(ok));
    rmse = sqrt(mean((paperSNR(ok) - recompSNR(ok)).^2));
    bias = mean(recompSNR(ok) - paperSNR(ok));
end

function printRow(label, r, rmse, bias, n)
    if isnan(r)
        fprintf('  %-62s  %5s  %6s  %6s  %4d\n', label, 'NaN', 'NaN', 'NaN', n);
    else
        fprintf('  %-62s  %5.3f  %6.1f  %+6.1f  %4d\n', label, r, rmse, bias, n);
    end
end

function idx = findInCache(cache, label)
    idx = find(strcmp({cache.label}, label), 1);
    if isempty(idx), idx = 0; end
end

function v = getFuncVersion(funcName)
    p = which(funcName);
    if isempty(p), v = sprintf('%s: not found', funcName); return; end
    d = dir(p);
    v = sprintf('%s | %s | modified: %s', funcName, p, d.date);
end

function entry = makeEntry(label, params, snrVec, r, rmse, bias, n, softwareVersion)
    entry.label           = label;
    entry.params          = params;
    entry.softwareVersion = softwareVersion;
    entry.snrVec          = snrVec;
    entry.r               = r;
    entry.rmse            = rmse;
    entry.bias            = bias;
    entry.n               = n;
    entry.runDate         = datestr(now);
end

function cache = updateCache(cache, cIdx, entry)
    if cIdx > 0
        cache(cIdx) = entry;
    else
        cache(end+1) = entry;
    end
end

function printSummary(cache)
    if isempty(cache), fprintf('\nNo results to summarise.\n'); return; end
    [~, ix] = sort([cache.r], 'descend');
    fprintf('\n--- Top 10 configurations by correlation ---\n');
    fprintf('  %-62s  %5s  %6s  %6s  %s\n', 'Configuration','r','RMSE','Bias','Date');
    fprintf('  %s\n', repmat('-',1,96));
    count = 0;
    for i = 1:numel(ix)
        if ~isfinite(cache(ix(i)).r), continue; end
        e = cache(ix(i));
        fprintf('  %-62s  %5.3f  %6.1f  %+6.1f  %s\n', ...
            e.label, e.r, e.rmse, e.bias, e.runDate);
        count = count + 1;
        if count >= 10, break; end
    end
end

