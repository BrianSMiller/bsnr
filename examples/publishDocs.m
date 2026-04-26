%% Publish bsnr documentation to docs/
%
% Publishes the method gallery and three published-data example scripts
% to HTML in the docs/ folder, then injects a link to bsnr.css so all
% pages share the documentation site style.
%
% Run from the examples/ folder:
%
%   cd('C:\analysis\bsnr\examples')
%   publishDocs

%% Configuration

docsDir   = fullfile(fileparts(mfilename('fullpath')), '..', 'docs');
cssFile   = fullfile(docsDir, 'bsnr.css');

scripts = {
    'bsnr_gallery.m'
    'snr_dcalls_casey2019.m'
    'snr_abw_sorp_library.m'
    'snr_abw_kerguelen2014_castro2024.m'
    'snr_abw_casey2019_commonground.m'
    'snr_parallel_guide_casey2019.m'
};

%% Publish each script

for k = 1:numel(scripts)
    fprintf('Publishing %s...\n', scripts{k});
    publish(scripts{k}, 'format', 'html', 'outputDir', docsDir);
end

%% Inject bsnr.css link into each published HTML
% publish() embeds styles inline with no external stylesheet hook,
% so we insert a <link> tag after the inline <style> block.

if ~exist(cssFile, 'file')
    warning('publishDocs:noCss', 'bsnr.css not found in docs/ — skipping stylesheet injection.');
else
    htmlFiles = dir(fullfile(docsDir, '*.html'));
    nInjected = 0;
    for k = 1:numel(htmlFiles)
        if strcmp(htmlFiles(k).name, 'index.html'), continue; end
        fpath = fullfile(htmlFiles(k).folder, htmlFiles(k).name);
        txt   = fileread(fpath);
        if contains(txt, 'bsnr.css')
            continue;   % already injected
        end
        txt = strrep(txt, '</style></head>', ...
            ['</style>' newline ...
             '<link rel="stylesheet" href="bsnr.css">' newline ...
             '</head>']);
        fid = fopen(fpath, 'w');
        fprintf(fid, '%s', txt);
        fclose(fid);
        nInjected = nInjected + 1;
    end
    fprintf('Stylesheet injected into %d HTML files.\n', nInjected);
end

fprintf('\nDone. Files written to:\n  %s\n', docsDir);
