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
% SNR METHODS
%   snrSpectrogram        - Mean band PSD (broadband tonal signals)
%   snrSpectrogramSlices  - Per-slice band power (Miller et al. 2021)
%   snrTimeDomain         - Bandpass FIR, mean instantaneous power
%   snrRidge              - Dominant ridge tracking (FM calls)
%   snrSynchrosqueeze     - Synchrosqueezed transform ridge (FM calls)
%   snrQuantiles          - Quantile-based estimator (experimental)
%
% DISPLAY
%   spectroAnnotationAndNoise  - Spectrogram with signal/noise overlays
%   plotTimeDomainPower        - Time-domain power time series
%
% UTILITIES
%   removeClicks          - Suppress impulsive noise (soft amplitude gate)
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
%   params.metadata = metaDataKerguelen2024;  % or simpleFlatMetadata()
%   result = snrEstimate(annot, params);
%   fprintf('Signal: %.1f dB re 1 uPa\n', result.signalBandLevel_dBuPa);
%
% BATCH PROCESSING
%
%   result = snrEstimate(annotTable, params);  % annotTable is a table
%   disp(result);                              % returns a result table
%
% EXAMPLES
%   See examples/bsnr_gallery.m for illustrated examples covering all
%   methods, FM calls, calibrated levels, and click removal. Publish to
%   HTML with:
%
%     publish('examples/bsnr_gallery.m', 'format', 'html', ...
%             'outputDir', 'examples/html')
%
% TEST SUITE
%   run('tests/run_tests.m')
%
% See also snrEstimate, snrSpectrogram, snrTimeDomain, snrRidge,
%          snrSynchrosqueeze, removeClicks, spectroAnnotationAndNoise.

% Brian Miller, Australian Antarctic Division.
% https://github.com/aaad/bsnr

function bsnr()
% Calling bsnr() displays this help text.
% Use 'help bsnr' or 'doc bsnr' for documentation.
help bsnr
end
