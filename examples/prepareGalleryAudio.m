%% prepareGalleryAudio.m
% Extract small audio clips from the IWC-SORP Annotated Library for use
% in bsnr_gallery.m. Run this once when you have the annotated library
% mounted; the resulting clips (~40KB each) are bundled with bsnr.
%
% Source: Miller et al. (2021) doi:10.26179/5e6056035c01b
% Clip parameters taken from makeSpectrograms.m (Miller 2021 fig. plots).
%
% Each clip is:
%   - 60s of audio centred on the first annotation of that call type
%   - Downsampled to 250 Hz (matching the annotated library)
%   - Saved as yyyy-mm-dd_HH-MM-SS.wav in examples/audio/<calltype>/
%
% The clip start time is embedded in the filename so that wavFolderInfo
% can find it automatically.

%% Library root — edit to match your local mount
libraryRoot = fullfile('S:\work\annotatedLibrary\SORP\');   % adjust as needed

%% Output folder
galleryDir = fileparts(mfilename('fullpath'));
audioDir   = fullfile(galleryDir, 'audio');

%% Clip definitions — from makeSpectrograms.m
% {subdir, sourceFile, clipStartSec (in source file), clipDurSec, label}
%
% clipStartSec = (file offset in makeSpectrograms) + (first annotation t0)
%                - prePadding, so the annotation sits ~10s into the clip
clips = {
    % ABW Z-call: Kerguelen2014, file offset 1510s, annot1 at ~16s in clip
    'abw_z'  'Kerguelen2014\wav\201_2014-03-01_12-00-00.wav'  1510   60  'ABW Z-call (Kerguelen 2014)'
    % ABW D-call: Kerguelen2015, file offset 1080s, annot1 at ~11.5s in clip
    'abw_d'  'kerguelen2015\wav\20150416_190000.wav'          1080   45  'ABW D-call (Kerguelen 2015)'
    % ABW Unit A: BallenyIslands2015, file offset 1492s, annot1 at ~9.7s
    'abw_a'  'BallenyIslands2015\wav\20150225_070000.wav'     1492   45  'ABW Unit-A (Balleny Islands 2015)'
    % ABW Unit B: ElephantIsland2014, file offset 45s, annot1 at ~15.7s
    'abw_b'  'ElephantIsland2014\wav\20140120_190000_AWI251-01_AU0231_250Hz.wav'  45  60  'ABW Unit-B (Elephant Island 2014)'
    % Fin 40Hz: Kerguelen2005, file offset 300s, annot1 at ~8.4s
    'bp_40'  'kerguelen2005\wav\20050424_000000.wav'          300    45  'Fin whale 40Hz (Kerguelen 2005)'
    % Fin 20Hz: BallenyIslands2015, file offset 3010s, annot1 at ~17.5s
    'bp_20'  'BallenyIslands2015\wav\20150322_000000.wav'     3010   60  'Fin whale 20Hz (Balleny Islands 2015)'
};

fprintf('Preparing gallery audio clips...\n');
fprintf('Source: %s\n\n', libraryRoot);

for i = 1:size(clips, 1)
    subdir      = clips{i,1};
    relFile     = clips{i,2};
    startSec    = clips{i,3};
    durSec      = clips{i,4};
    label       = clips{i,5};

    srcFile = fullfile(libraryRoot, relFile);
    outDir  = fullfile(audioDir, subdir);

    fprintf('  %s\n', label);

    if ~exist(srcFile, 'file')
        fprintf('    [SKIP] source not found: %s\n', srcFile);
        continue;
    end

    % Read and downsample
    info    = audioinfo(srcFile);
    origFs  = info.SampleRate;
    targetFs = 250;
    startSamp = round(startSec * origFs) + 1;
    stopSamp  = min(startSamp + round(durSec * origFs), info.TotalSamples);

    wav = audioread(srcFile, [startSamp stopSamp]);
    wav = wav(:,1);   % mono

    if origFs ~= targetFs
        wav = decimate(wav, origFs / targetFs);
    end

    % Output filename — clip start time as yyyy-mm-dd_HH-MM-SS
    % Use the WAV file timestamp + offset
    [~, wavName] = fileparts(srcFile);
    try
        fileStart = filenameToTimeStamp(wavName, guessFileNameTimestamp(srcFile));
    catch
        fileStart = now();
    end
    clipStart    = fileStart + startSec / 86400;
    clipStartStr = datestr(clipStart, 'yyyy-mm-dd_HH-MM-SS');

    if ~exist(outDir, 'dir'), mkdir(outDir); end
    outFile = fullfile(outDir, [clipStartStr '.wav']);
    audiowrite(outFile, wav / max(abs(wav)) * 0.9, targetFs, 'BitsPerSample', 16);
    fprintf('    -> %s  (%.0f s, %d Hz)\n', [clipStartStr '.wav'], durSec, targetFs);
end

fprintf('\nDone. Clips saved to: %s\n', audioDir);
fprintf('Now run bsnr_gallery.m\n');
