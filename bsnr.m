% bsnr — Bioacoustic SNR Estimation Toolbox
% Version 0.3.0-beta
%
% Estimates signal-to-noise ratio for bioacoustic detections in
% hydrophone recordings. Accepts time-frequency bounded detections
% (annotations, detections, or any struct with t0, tEnd, freq fields)
% and returns SNR in dB along with signal and noise power estimates.
% When instrument calibration metadata is provided, returns calibrated
% acoustic levels in dB re 1 µPa.
%
% PUBLIC API
%   snrEstimate           - Estimate SNR for one or more detections.
%                           Accepts struct or name-value pairs:
%                             snrEstimate(annot, 'snrType', 'spectrogramSlices', 'freq', [25 29])
%   trimAnnotation        - Trim annotation bounds to central signal energy
%                           before passing to snrEstimate. Accepts name-value pairs:
%                             trimAnnotation(annot, 'energyPercentile', 10, 'showPlot', true)
%   removeClicks          - Suppress impulsive noise (PAMGuard soft amplitude gate)
%   readTethysDetections  - Convert Tethys Detections XML or struct to bsnr
%                           annotation array
%   writeTethysXml        - Write bsnr result table as Tethys-compatible
%                           Detections XML (no Nilus/server required)
%
% SNR METHODS (selected via snrType parameter)
%   'spectrogram'        - Mean band PSD; simple power ratio or Lurton formula
%   'spectrogramSlices'  - Per-slice band power (robust to transients)
%   'timeDomain'         - Bandpass FIR, mean instantaneous power
%   'ridge'              - Dominant ridge tracking for FM calls (per-bin SNR)
%   'synchrosqueeze'     - Synchrosqueezed STFT ridge, sharper FM tracking
%   'quantiles'          - Within-window percentile estimator (no noise window needed)
%   'nist'               - Frame energy histogram; NIST (1992) STNR
%
%   Method implementations are in private/ and not called directly.
%
% DISPLAY (controlled via params.displayType)
%   'spectrogram'  — TF spectrogram with overlays (default for most methods)
%   'timeSeries'   — per-slice band power vs time
%   'histogram'    — signal and noise slice power distributions
%
% EXPERIMENTAL (not integrated into snrEstimate)
%   experimental/snrWADA  - WADA-SNR (Kim & Stern 2008); no noise window required
%
% QUICK START
%
%   % Use a pre-extracted Z-call clip included in examples/audio/
%   % (see trimAnnotation for tightening annotation bounds before SNR estimation)
%   audioDir = fullfile(fileparts(which('bsnr')), 'examples', 'audio', 'abw_z');
%   sf = wavFolderInfo(audioDir, '', false, false);
%
%   annot.soundFolder    = audioDir;
%   annot.t0             = sf(1).startDate + 17/86400;  % 17 s into clip
%   annot.tEnd           = annot.t0 + 21/86400;          % 21 s duration
%   annot.duration       = 21;
%   annot.freq           = [17 28];   % Hz
%   annot.channel        = 1;
%   annot.classification = 'ABW Z';
%
%   snr = snrEstimate(annot);
%   fprintf('SNR = %.1f dB\n', snr);
%
%   % Show spectrogram with signal/noise overlays
%   params.showClips      = true;
%   params.pauseAfterPlot = false;
%   params.verbose        = false;   % suppress progress output
%   snr = snrEstimate(annot, params);
%
%   % Lurton formula with spectrogram display
%   params.useLurton   = true;
%   snr = snrEstimate(annot, params);
%
% STFT PARAMETERS
%
%   params.nfft and params.nOverlap are the primary STFT parameters.
%   For batch processing, always set params.nfft explicitly — a constant
%   nfft is required for SNR values to be comparable across annotations.
%
%   params.nfft    = 512;   % FFT length (samples)
%   params.nOverlap = 384;  % overlap (default: floor(nfft * 0.75))
%
%   When not set, nfft is derived from params.nSlices (default 30) and
%   the median annotation duration, with a warning.
%
% CALIBRATED LEVELS
%
%   params.calibration = metaDataCasey2019();   % or your instrument calibration struct
%   result = snrEstimate([annot; annot], params);
%   fprintf('Signal: %.1f dB re 1 uPa\n', result.signalBandLevel_dBuPa(1));
%
% NOISE WINDOW
%
%   By default, the noise window is placed symmetrically before and after
%   the detection with a 0.5 s gap (params.noiseDelay = 0.5). Alternatives:
%
%   params.noiseLocation   = 'before';   % single window before signal
%   params.noiseDuration_s = 25;         % 25 s window (default: annotation duration)
%   params.noiseDelay      = 1.0;        % gap in seconds
%
% BATCH PROCESSING
%
%   result = snrEstimate(annotTable, 'snrType', 'spectrogramSlices');
%   disp(result);   % returns a result table with snr, signalRMSdB, noiseRMSdB
%
% RESOLVED PARAMETERS
%
%   [snr, ~, ~, ~, ~, resolvedParams] = snrEstimate(annot);
%   resolvedParams.nfft     % actual FFT length used (derived if not set explicitly)
%   resolvedParams.nOverlap % actual overlap used
%   resolvedParams.snrType  % method used
%
%   resolvedParams captures all parameters after defaults and nfft derivation.
%   Record it alongside results for reproducibility.
%
% DESIGN PHILOSOPHY
%
%   Correct, clear, and consistent — in that order.
%
%   Correct     Analytical tests verify known SNR values against
%               closed-form solutions. Includes comparison with and
%               predominantly faithful reproduction of published estimates.
%
%   Clear       Well-documented code with explicit parameter names and
%               tab-completion. Diagnostic plots show exactly what was
%               measured. resolvedParams helps record which parameters
%               were actually used.
%
%   Consistent  Shared conventions across functions make it easier to
%               learn one part and apply that knowledge elsewhere.
%               Where possible, outputs align with Tethys and ASA
%               passive acoustic metadata standards.
%
% REFERENCES
%
%   Simple power ratio (snrType='spectrogram', useLurton=false):
%     Miller et al. (2022). Deep Learning Algorithm Outperforms Experienced
%     Human Observer at Detection of Blue Whale D-calls. Remote Sensing in
%     Ecology and Conservation. https://doi.org/10.1002/rse2.297
%
%     Castro et al. (2024). Beyond Counting Calls: Estimating Detection
%     Probability for Antarctic Blue Whales. Frontiers in Marine Science.
%     https://doi.org/10.3389/fmars.2024.1406678
%
%   Lurton formula (snrType='spectrogram', useLurton=true):
%     Lurton, X. (2010). An Introduction to Underwater Acoustics:
%     Principles and Applications (2nd ed.). Springer-Praxis. eq. 6.26
%
%   NIST STNR histogram method (snrType='nist'):
%     NIST (1992). Signal-to-Noise Ratio utility (stnr).
%     Speech Quality Assurance Package.
%     https://labrosa.ee.columbia.edu/~dpwe/tmp/nist/doc/stnr.txt
%     Also implemented independently in Raven Pro 1.6.1 as 'SNR NIST Quick'.
%     https://www.ravensoundsoftware.com/knowledge-base/signal-to-noise-ratio-snr-nist-quick-method/
%
% EXAMPLES
%   See examples/bsnr_gallery.m for illustrated examples covering all
%   methods, display types, calibrated levels, click removal, and real
%   Antarctic baleen whale recordings. Publish to HTML with:
%
%     cd examples
%     publishDocs
%
% ROADMAP
%
%   See todo.md in the repository root, or:
%   https://github.com/BrianSMiller/bsnr/blob/main/todo.md
%
%   Published-data examples with paper comparisons:
%     snr_dcalls_casey2019.m              — Miller et al. (2022)
%     snr_abw_sorp_library.m              — Miller et al. (2021)
%     snr_abw_kerguelen2014_castro2024.m  — Castro et al. (2024)
%     snr_abw_casey2019_commonground.m    — Miller et al. (in press)
%
% TEST SUITE
%   run('run_tests.m')
%
% See also snrEstimate, trimAnnotation, removeClicks.

% Brian Miller, Australian Antarctic Division.
% https://github.com/BrianSMiller/bsnr

function bsnr()
% Calling bsnr() displays this help text.
% Use 'help bsnr' or 'doc bsnr' for documentation.
help bsnr
end
