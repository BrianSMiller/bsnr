function test_snrEstimate_scalar()
% Integration tests for snrEstimate() with scalar annotation input.
%
% Writes real temporary WAV files and calls the full stack including
% wavFolderInfo and getAudioFromFiles. Each test creates its own fixture
% and cleans up afterwards.

fprintf('\n=== test_snrEstimate_scalar ===\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (1) Basic scalar call returns correct output types
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annot, cleanup] = createTestFixture();
try
    params = struct('snrType', 'spectrogram', 'showClips', false);
    [snr, rmsSignal, rmsNoise, noiseVar, fileInfo] = snrEstimate(annot, params);

    assert(isscalar(snr),       'scalar: snr should be scalar');
    assert(isscalar(rmsSignal), 'scalar: rmsSignal should be scalar');
    assert(isscalar(rmsNoise),  'scalar: rmsNoise should be scalar');
    assert(isscalar(noiseVar),  'scalar: noiseVar should be scalar');
    assert(isstruct(fileInfo),  'scalar: fileInfo should be a struct');
    assert(isfinite(snr),       'scalar: snr should be finite for valid signal');
    assert(snr > 0,             'scalar: snr should be positive for high-SNR input');
    fprintf('  [PASS] returns correct output types, SNR = %.2f dB\n', snr);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (2) Simple SNR formula recovers approximately correct power ratio
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annot, cleanup] = createTestFixture('signalRMS', 1.0, 'noiseRMS', 0.1);
try
    % True power-ratio SNR = 10*log10(1.0^2 / 0.1^2) = 20 dB
    trueSNR = 20;
    params  = struct('snrType', 'spectrogram', 'showClips', false, ...
                     'useLurton', false);
    [snr, ~, ~, ~, ~] = snrEstimate(annot, params);

    assert(isfinite(snr) && snr > 0, ...
        sprintf('simple formula: expected positive SNR, got %.2f dB', snr));
    % The spectrogram integrates PSD including spectral leakage from the
    % pure tone, so allow wider tolerance than the theoretical power ratio.
    assert(abs(snr - trueSNR) < 10, ...
        sprintf('simple formula: SNR %.2f dB is >10 dB from true %.2f dB', snr, trueSNR));
    fprintf('  [PASS] simple SNR formula: %.2f dB (true = %.2f dB)\n', snr, trueSNR);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (3) Lurton formula gives higher values than simple formula
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Use very high SNR so (S-N)^2/noiseVar reliably exceeds S/N.
% At moderate SNR the Lurton estimator can be lower than simple.
[annot, cleanup] = createTestFixture('signalRMS', 10.0, 'noiseRMS', 0.01);
try
    paramsSimple = struct('snrType', 'spectrogram', 'showClips', false, 'useLurton', false);
    paramsLurton = struct('snrType', 'spectrogram', 'showClips', false, 'useLurton', true);

    [snrSimple, ~, ~, ~, ~] = snrEstimate(annot, paramsSimple);
    [snrLurton, ~, ~, ~, ~] = snrEstimate(annot, paramsLurton);

    assert(isfinite(snrSimple) && isfinite(snrLurton), ...
        'both formulas should return finite SNR');
    assert(snrLurton > snrSimple, ...
        sprintf('Lurton (%.2f dB) should exceed simple (%.2f dB) for high-SNR input', ...
        snrLurton, snrSimple));
    fprintf('  [PASS] Lurton=%.2f dB > simple=%.2f dB\n', snrLurton, snrSimple);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (4) params.freq override: in-band SNR exceeds out-of-band SNR
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annot, cleanup] = createTestFixture('toneFreqHz', 200, 'freq', [150 250]);
try
    paramsIn  = struct('snrType', 'spectrogram', 'showClips', false, 'freq', [150 250]);
    paramsOut = struct('snrType', 'spectrogram', 'showClips', false, 'freq', [600 800]);

    [snrIn,  ~, ~, ~, ~] = snrEstimate(annot, paramsIn);
    [snrOut, ~, ~, ~, ~] = snrEstimate(annot, paramsOut);

    assert(isfinite(snrIn) && isfinite(snrOut), 'both freq bands should return finite SNR');
    assert(snrIn > snrOut, ...
        sprintf('in-band (%.2f dB) should exceed out-of-band (%.2f dB)', snrIn, snrOut));
    fprintf('  [PASS] params.freq override: in-band=%.2f dB > out-of-band=%.2f dB\n', snrIn, snrOut);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (5) Missing audio path returns NaN cleanly
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annot, cleanup] = createTestFixture();
try
    badAnnot             = annot;
    badAnnot.soundFolder = fullfile(tempdir, 'nonexistent_folder_xyz');
    params               = struct('snrType', 'spectrogram', 'showClips', false);

    [snr, rmsSignal, ~, ~, fileInfo] = snrEstimate(badAnnot, params);

    assert(isnan(snr),        'bad path: snr should be NaN');
    assert(isnan(rmsSignal),  'bad path: rmsSignal should be NaN');
    assert(isempty(fileInfo), 'bad path: fileInfo should be empty');
    fprintf('  [PASS] missing audio path returns NaN without error\n');
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (6) showClips = false opens no figures
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annot, cleanup] = createTestFixture();
try
    nFigsBefore = numel(findobj('type', 'figure'));
    snrEstimate(annot, struct('snrType', 'spectrogram', 'showClips', false));
    nFigsAfter = numel(findobj('type', 'figure'));
    assert(nFigsAfter == nFigsBefore, ...
        'showClips=false should not open any new figures');
    fprintf('  [PASS] showClips=false opens no figures\n');
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (7) Table input is accepted
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[annot, cleanup] = createTestFixture();
try
    [snr, ~, ~, ~, ~] = snrEstimate(struct2table(annot), ...
        struct('snrType', 'spectrogram', 'showClips', false));
    assert(isfinite(snr), 'table input: should return finite SNR');
    fprintf('  [PASS] table input accepted, SNR = %.2f dB\n', snr);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (8) All four snrType values run without error
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

snrTypes = {'spectrogram', 'spectrogramSlices', 'quantiles', 'nist', 'wada', 'timeDomain', 'ridge', 'synchrosqueeze'};
for k = 1:length(snrTypes)
    [annot, cleanup] = createTestFixture();
    try
        [snr, ~, ~, ~, ~] = snrEstimate(annot, ...
            struct('snrType', snrTypes{k}, 'showClips', false));
        assert(isscalar(snr), sprintf('snrType=%s: should return scalar', snrTypes{k}));
        fprintf('  [PASS] snrType=''%s'': SNR = %.2f dB\n', snrTypes{k}, snr);
    catch err; cleanup(); rethrow(err); end
    cleanup();
end

fprintf('\n=== test_snrEstimate_scalar PASSED ===\n');
end
