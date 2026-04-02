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
%   snrSpectrogramSlices  - Per-slice band power median (robust to transients)
%   snrTimeDomain         - Bandpass FIR, mean instantaneous power
%   snrRidge              - Dominant ridge tracking for FM calls
%   snrSynchrosqueeze     - Synchrosqueezed STFT ridge (sharper FM tracking)
%   snrQuantiles          - Within-window percentile estimator (no noise window)
%
% SNR METHODS (speech/engineering, adapted for bioacoustics)
%   snrNIST               - Frame energy histogram; Ellis (2011) / NIST STNR
%
% DISPLAY
%   spectroAnnotationAndNoise  - Spectrogram with signal/noise overlays;
%                                contour overlay for quantiles method
%   plotTimeDomainPower        - Time-domain bandpass power time series
%
% UTILITIES
%   removeClicks          - Suppress impulsive noise (PAMGuard soft amplitude gate)
%   simpleFlatMetadata    - Example calibration metadata struct (flat 20 dB gain)
%
% QUICK START
%
%   annot.soundFolder = 'D:\recordings\site1';
%   annot.t0          = datenum([2024 03 15 10 30 00]);
%   annot.tEnd        = datenum([2024 03 15 10 30 02]);
%   annot.duration    = 2;
%   annot.freq        = [80 120];   % Hz
%   annot.channel     = 1;
%
%   [snr, rmsSignal, rmsNoise] = snrEstimate(annot);
%   fprintf('SNR = %.1f dB\n', snr);
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
%   the detection with a 0.5 s gap (params.noiseDelay = 0.5). To place
%   noise only before the detection:
%
%   params.noiseDuration = 'before';
%   params.noiseDelay    = 1.0;   % 1 s gap
%
% BATCH PROCESSING
%
%   result = snrEstimate(annotTable, params);   % annotTable is a table
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
%   methods, FM calls, calibrated levels, and click removal. Publish to
%   PDF with:
%
%     publish('examples/bsnr_gallery.m', 'format', 'pdf', 'outputDir', '.\')
%
% TEST SUITE
%   run('tests/run_tests.m')
%
% See also snrEstimate, snrSpectrogram, snrTimeDomain, snrRidge,
%          snrSynchrosqueeze, snrQuantiles, snrNIST, removeClicks.

% Brian Miller, Australian Antarctic Division.
% https://github.com/aaad/bsnr

function bsnr()
% Calling bsnr() displays this help text.
% Use 'help bsnr' or 'doc bsnr' for documentation.
help bsnr
end
