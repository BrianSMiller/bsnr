function test_calibration()
% Test that snrEstimate correctly recovers acoustic levels (dB re 1 µPa)
% when instrument calibration metadata is applied.
%
% Uses createCalibratedTestFixture to generate a synthetic recording with
% known source levels, then checks that snrEstimate returns:
%   - Signal level within ±3 dB of the true source level
%   - Noise level within ±3 dB of the true noise level
%   - SNR within ±3 dB of the true acoustic SNR
%
% Test signal: 100 Hz tone at 122 dB re 1 µPa in noise at 90 dB re 1 µPa
%   True SNR = 32 dB
%
% Instrument: Kerguelen 2024 AAD whale recorder
%   Hydrophone sensitivity: -165.9 dB re V/µPa
%   ADC peak voltage: 1.5 V
%   Frontend gain: ~20 dB flat, AC coupling ~5 Hz, AA filter ~5 kHz
%   Sample rate: 12000 Hz

fprintf('\n=== test_calibration ===\n');


trueSigLevel = 122;   % dB re 1 µPa
trueNoiseLvl  = 90;   % dB re 1 µPa
trueSNRdB     = trueSigLevel - trueNoiseLvl;   % 32 dB
tolerance     = 3;    % dB

[annot, metadata, cleanup] = createCalibratedTestFixture( ...
    'signalLeveldB',  trueSigLevel, ...
    'noiseLeveldB',   trueNoiseLvl, ...
    'toneFreqHz',     100, ...
    'freq',           [80 120], ...
    'durationSec',    4, ...
    'classification', sprintf('Cal: %d dB re 1uPa signal, %d dB re 1uPa noise', ...
        trueSigLevel, trueNoiseLvl));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Test each SNR method with calibration
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Test spectrogram-based methods with absolute level assertions.
% rmsSignal from PSD methods is mean PSD in uPa^2/Hz (after calibration).
% For band-limited noise: total power = mean_PSD * bandwidth
% So: 10*log10(rmsSignal * bandwidth) recovers the source level in dB re 1 uPa.
% timeDomain does not apply calibration so only its SNR is checked.
freq      = [80 120];

plotParams.pre        = 1;
plotParams.post       = 1;
plotParams.yLims      = [0 500];
plotParams.freq       = freq;
plotParams.win        = floor(metadata.sampleRate / 4);
plotParams.overlap    = floor(plotParams.win * 0.75);

% timeDomain: absolute levels are reliable (total power in uPa^2).
% spectrogram/spectrogramSlices: absolute signal level is unreliable for
% tonal signals (tone energy concentrated in 1 FFT bin, mean(PSD)*bw underestimates
% by nBins). Noise level IS reliable for broadband noise. SNR is reliable for both.
allMethods = {'timeDomain', 'spectrogram', 'spectrogramSlices'};
for k = 1:numel(allMethods)
    snrType = allMethods{k};
    params = struct( ...
        'snrType',       snrType, ...
        'showClips',     false, ...
        'metadata',      metadata, ...
        'freq',          freq, ...
        'plotParams', plotParams);
    try
        % Use vector input to get result table with acoustic level columns
        [result, ~, ~, ~, ~] = snrEstimate([annot; annot], params);
        snr    = result.snr(1);

        assert(isfinite(snr), ...
            sprintf('%s: SNR is NaN — calibration pathway may have failed', snrType));

        % SNR within tolerance
        snrErr = abs(snr - trueSNRdB);
        assert(snrErr <= tolerance, ...
            sprintf('%s: SNR %.1f dB, expected %.1f (err=%.1f dB)', ...
            snrType, snr, trueSNRdB, snrErr));

        % Acoustic level columns should be present and correct
        assert(ismember('signalBandLevel_dBuPa', result.Properties.VariableNames), ...
            sprintf('%s: signalBandLevel_dBuPa column missing from result table', snrType));
        sigLevel   = result.signalBandLevel_dBuPa(1);
        noiseLevel = result.noiseBandLevel_dBuPa(1);
        sigErr     = abs(sigLevel   - trueSigLevel);
        noiseErr   = abs(noiseLevel - trueNoiseLvl);
        % All methods now correctly recover absolute levels via sum(PSD)*df integration
        assert(sigErr <= tolerance, ...
            sprintf('%s: signal %.1f dB re 1uPa, expected %.1f (err=%.1f dB)', ...
            snrType, sigLevel, trueSigLevel, sigErr));
        assert(noiseErr <= tolerance, ...
            sprintf('%s: noise %.1f dB re 1uPa, expected %.1f (err=%.1f dB)', ...
            snrType, noiseLevel, trueNoiseLvl, noiseErr));
        fprintf('  [PASS] %s: SNR=%.1f dB (err=%.1f), signal=%.1f dBuPa (err=%.1f), noise=%.1f dBuPa (err=%.1f)\n', ...
            snrType, snr, snrErr, sigLevel, sigErr, noiseLevel, noiseErr);
    catch err; cleanup(); rethrow(err); end
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Verify uncalibrated gives wrong levels (sanity check)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('--- Sanity check: uncalibrated should NOT recover correct levels ---\n');
params_nocal = struct( ...
    'snrType',       'spectrogram', ...
    'showClips',     false, ...
    'plotParams', plotParams);
result_nocal   = snrEstimate(annot, params_nocal);
snr_nocal      = result_nocal.snr(1);
sigLevel_nocal = result_nocal.signalRMSdB(1);   % dBFS, uncalibrated
assert(abs(sigLevel_nocal - trueSigLevel) > tolerance, ...
    'Uncalibrated level should NOT match true acoustic level');
fprintf('  [PASS] Uncalibrated signal = %.1f dBFS (correctly != %.1f dB re 1uPa)\n', ...
    sigLevel_nocal, trueSigLevel);
fprintf('         Calibrated SNR = %.1f dB, Uncalibrated SNR = %.1f dB\n', ...
    trueSNRdB, snr_nocal);
fprintf('         (SNR should be similar since calibration cancels in the ratio)\n');

cleanup();
fprintf('\n=== test_calibration PASSED ===\n');
end
