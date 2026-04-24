function test_snrEstimate_scalar()
% Integration tests for snrEstimate() with scalar annotation input.
%
% snrEstimate always returns a result table now — even for a single annotation.
% These tests verify output shape, column presence, and correctness.

fprintf('\n=== test_snrEstimate_scalar ===\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (1) Single annotation returns a 1-row table with required columns
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[annot, cleanup] = createTestFixture();
try
    result = snrEstimate(annot, 'snrType', 'spectrogram', 'showClips', false);
    assert(istable(result),            'scalar: output should be a table');
    assert(height(result) == 1,        'scalar: table should have 1 row');
    for col = {'snr', 'signalRMSdB', 'noiseRMSdB', 'noiseVar'}
        assert(ismember(col{1}, result.Properties.VariableNames), ...
            sprintf('scalar: table missing column %s', col{1}));
    end
    assert(isfinite(result.snr(1)),    'scalar: snr should be finite');
    assert(result.snr(1) > 0,         'scalar: snr should be positive for high-SNR input');
    fprintf('  [PASS] 1-row table with required columns, SNR = %.2f dB\n', result.snr(1));
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (2) Simple SNR formula recovers approximately correct power ratio
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[annot, cleanup] = createTestFixture('signalRMS', 1.0, 'noiseRMS', 0.1);
try
    trueSNR = 20;   % 10*log10(1.0^2 / 0.1^2)
    result  = snrEstimate(annot, 'snrType', 'spectrogram', ...
        'showClips', false, 'useLurton', false);
    snr = result.snr(1);
    assert(isfinite(snr) && snr > 0, ...
        sprintf('simple formula: expected positive SNR, got %.2f dB', snr));
    assert(abs(snr - trueSNR) < 10, ...
        sprintf('simple formula: SNR %.2f dB is >10 dB from true %.2f dB', snr, trueSNR));
    fprintf('  [PASS] simple SNR formula: %.2f dB (true = %.2f dB)\n', snr, trueSNR);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (3) resolvedParams returned and contains nfft
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[annot, cleanup] = createTestFixture();
try
    [result, ~, ~, ~, ~, rp] = snrEstimate(annot, 'showClips', false);
    assert(isstruct(rp),                 'scalar: resolvedParams should be a struct');
    assert(isfield(rp, 'nfft'),          'scalar: resolvedParams.nfft missing');
    assert(~isempty(rp.nfft) && rp.nfft > 0, ...
        sprintf('scalar: resolvedParams.nfft should be positive, got %s', mat2str(rp.nfft)));
    assert(rp.nfft == 2^round(log2(rp.nfft)), ...
        'scalar: resolvedParams.nfft should be a power of 2');
    fprintf('  [PASS] resolvedParams.nfft = %d (power of 2)\n', rp.nfft);
catch err; cleanup(); rethrow(err); end
cleanup();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% (4) Invalid annotation (outside file bounds) returns NaN row, no error
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[annot, cleanup] = createTestFixture();
try
    annotBad      = annot;
    annotBad.t0   = datenum('2099-01-01', 'yyyy-mm-dd');
    annotBad.tEnd = annotBad.t0 + annot.duration / 86400;

    result = snrEstimate(annotBad, 'showClips', false, 'verbose', false);
    assert(istable(result),            'invalid: should return a table');
    assert(height(result) == 1,        'invalid: table should have 1 row');
    assert(isnan(result.snr(1)),       'invalid: out-of-range annot should give NaN');
    fprintf('  [PASS] out-of-range annotation returns NaN gracefully\n');
catch err; cleanup(); rethrow(err); end
cleanup();

fprintf('\n=== test_snrEstimate_scalar PASSED ===\n');
end
