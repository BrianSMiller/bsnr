% bsnr — Bioacoustic SNR Estimation Toolbox
%
% Estimates signal-to-noise ratio for bioacoustic detections in
% hydrophone recordings. Accepts time-frequency bounded detections
% (annotations, detections, or any struct with t0, tEnd, freq fields)
% and returns SNR in dB along with signal and noise power estimates.
% When instrument calibration metadata is provided, returns calibrated
% acoustic levels in dB re 1 µPa.
%
% MAIN FUNCTION
%   snrEstimate           - Estimate SNR for one or more detections
%
% SNR METHODS (bioacoustic)
%   snrSpectrogram        - Mean band PSD; simple power ratio or Lurton formula
%                           Miller et al. (2021, 2022, 2024)
%   snrSpectrogramSlices  - Per-slice band power (robust to transients)
%   snrTimeDomain         - Bandpass FIR, mean instantaneous power
%   snrRidge              - Dominant ridge tracking for FM calls (per-bin SNR)
%   snrSynchrosqueeze     - Synchrosqueezed STFT ridge, sharper FM tracking (per-bin SNR)
%   snrQuantiles          - Within-window percentile estimator (no noise window needed)
%
% SNR METHODS (speech/engineering, adapted for bioacoustics)
%   snrHistogram          - Frame energy histogram; Ellis (2011) / NIST STNR
%
% DISPLAY
%   spectroAnnotationAndNoise  - Spectrogram with signal/noise overlays
%   plotBandSamplePower        - Per-sample bandpass power trace (timeDomain method)
%
%   Display type is controlled via params.displayType:
%     'spectrogram'  — TF spectrogram with overlays (default for most methods)
%     'timeSeries'   — per-slice band power vs time
%     'histogram'    — signal and noise slice power distributions
%
% UTILITIES
%   removeClicks          - Suppress impulsive noise (PAMGuard soft amplitude gate)
%   simpleFlatMetadata    - Example calibration metadata struct (flat 20 dB gain)
%
% EXPERIMENTAL (not integrated into snrEstimate)
%   experimental/snrWADA  - WADA-SNR (Kim & Stern 2008); amplitude distribution
%                           analysis; does not require a separate noise window
%
% QUICK START
%
%   % Use a pre-extracted Z-call clip from the bsnr gallery audio
%   % (run prepareGalleryAudio.m first, or place clips in examples/audio/)
%   audioDir = fullfile(fileparts(which('bsnr')), 'examples', 'audio', 'abw_z');
%   sf = wavFolderInfo(audioDir, '', false, false);
%
%   annot.soundFolder    = audioDir;
%   annot.t0             = sf(1).startDate + 17/86400;   % 17 s into clip
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
%   snr = snrEstimate(annot, params);
% 
%   % Lurton formula with histogram display
%   params.useLurton   = true;
%   params.displayType = 'spectrogram';
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
%   params.metadata = simpleFlatMetadata();   % or your instrument metadata
%   result = snrEstimate([annot; annot], params);
%   fprintf('Signal: %.1f dB re 1 uPa\n', result.signalBandLevel_dBuPa(1));
%
% NOISE WINDOW
%
%   By default, the noise window is placed symmetrically before and after
%   the detection with a 0.5 s gap (params.noiseDelay = 0.5). Alternatives:
%
%   params.noiseDuration = 'before';      % single window before signal
%   params.noiseDuration = '25sBefore';   % 25 s window before detection
%   params.noiseDelay    = 1.0;           % gap in seconds
%
% BATCH PROCESSING
%
%   result = snrEstimate(annotTable, params);   % annotTable is a table or struct array
%   disp(result);                               % returns a result table
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
%     Miller et al. (2021). An Open Access Dataset for Developing Automated
%     Detectors of Antarctic Baleen Whale Sounds. Scientific Reports 11, 806.
%     https://doi.org/10.1038/s41598-020-78995-8
%
%   NIST STNR histogram method (snrType='nist'):
%     Ellis, D.P.W. (2011). nist_stnr_m.m. LabROSA/Columbia University.
%     https://labrosa.ee.columbia.edu/~dpwe/tmp/nist/doc/stnr.txt
%
% EXAMPLES
%   See examples/bsnr_gallery.m for illustrated examples covering all
%   methods, display types, calibrated levels, click removal, and real
%   Antarctic baleen whale recordings. Publish to HTML with:
%
%     cd examples
%     publish('bsnr_gallery.m', 'format', 'html', 'outputDir', '..\docs')
%     movefile('..\docs\bsnr_gallery.html', '..\docs\index.html')
%
%   Published-data examples with paper comparisons:
%     snr_dcalls_casey2019.m              — Miller et al. (2022)
%     snr_abw_sorp_library.m              — Miller et al. (2021)
%     snr_abw_kerguelen2014_castro2024.m  — Castro et al. (2024)
%
% TEST SUITE
%   run('tests/run_tests.m')
%
% See also snrEstimate, snrSpectrogram, snrTimeDomain, snrRidge,
%          snrSynchrosqueeze, snrQuantiles, snrHistogram, removeClicks.

% Brian Miller, Australian Antarctic Division.
% https://github.com/BrianSMiller/bsnr

function bsnr()
% Calling bsnr() displays this help text.
% Use 'help bsnr' or 'doc bsnr' for documentation.
help bsnr
end
