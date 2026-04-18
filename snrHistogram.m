function [rmsSignal, rmsNoise, noiseVar, histogramData] = snrHistogram( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate SNR using a frame-energy histogram method.
%
% Implements the NIST STNR preferred algorithm as described in the NIST Speech
% Quality Assurance Package (NIST 1992). An independent implementation of the
% same base algorithm is available in Raven Pro 1.6.1 as 'SNR NIST Quick'
% (Cornell Lab of Ornithology). Bioacousticians familiar with Raven's SNR
% measurement will find bsnr's nist method directly comparable.
% The method is widely
% used in speech quality assessment and made available to bioacoustics users
% through Raven Pro 1.6.1 (Cornell Lab of Ornithology) as 'SNR NIST Quick'.
%
% ALGORITHM
%   1. Bandpass filter to the annotation frequency band (bsnr adaptation;
%      original operates on full-spectrum energy).
%   2. Compute RMS energy in overlapping 20 ms frames (10 ms advance).
%   3. Build a histogram of frame energies in dB (500 bins, -28 to +97 dB)
%      and smooth it with a 15-bin rectangular window.
%   4. Fit a raised cosine to the leftmost (noise) peak to estimate the
%      mean noise energy.
%   5. Locate the signal energy at the 95th percentile of the cumulative
%      histogram.
%   6. SNR = 20*log10(signal_rms / noise_rms).
%
% LIMITATIONS
%   This is a crude approximation. NIST does not endorse its use.
%   It assumes the recording contains a mixture of noise-only and
%   signal-active frames — the histogram will be bimodal only if enough
%   of both are present. For short clips with high SNR it may overestimate;
%   for clips without clear bimodality it may give erratic results.
%   Not available in Python librosa (which focuses on music analysis);
%
% REFERENCES
%   NIST STNR algorithm:
%     https://www.nist.gov/itl/iad/mig/nist-speech-signal-noise-ratio-measurements
%     https://labrosa.ee.columbia.edu/~dpwe/tmp/nist/doc/stnr.txt
%   Raven Pro implementation:
%     https://www.ravensoundsoftware.com/knowledge-base/
%             signal-to-noise-ratio-snr-nist-quick-method/
%
% INPUTS
%   sigAudio    Signal audio samples (column vector)
%   noiseAudio  Noise audio samples — used to set noise histogram reference
%   nfft        FFT length (not used directly; kept for interface consistency)
%   nOverlap    Window overlap (not used; kept for interface consistency)
%   sampleRate  Sample rate in Hz
%   freq        [lowHz highHz] bandpass filter range
%   metadata    Calibration metadata struct, or [] for no calibration
%
% OUTPUTS
%   rmsSignal  Signal power estimate (linear; uPa^2 if calibrated)
%   rmsNoise   Noise power estimate  (linear; uPa^2 if calibrated)
%   noiseVar   Variance of noise frame energies
%   histogramData   Struct with fields for plotting and diagnostics:
%                .binCentres    histogram bin centres (dB, NIST internal scale)
%                .histSmooth    smoothed histogram counts (normalised to density
%                               by plotHistogramSNR; stored raw here)
%                .histRaw       pre-smoothing bin counts (before medfilt + boxcar)
%                .noisedB       estimated noise level (dB, NIST internal scale)
%                .signaldB      estimated signal level (dB, NIST internal scale)
%                .noiseWidth_dB half-width at half-maximum of noise peak (dB)
%                .noisePeakBin  bin index of noise peak (regression guard: should
%                               be > BINS/2 for typical audio; see test_snrMethods)
%              Empty struct if signal window is too short for the histogram
%              (< 10 frames); caller should check isfield(histogramData,'binCentres').

if nargin < 7, metadata = []; end

%% Constants (from stnr.txt / snr.h)
FRAME_MS   = 20.0;    % frame width in milliseconds
BINS       = 500;     % histogram bins
LOW_dB     = -28.125; % histogram lower edge (dB)
HIGH_dB    = 96.875;  % histogram upper edge (dB)
SMOOTH_BINS = 15;     % histogram smoothing half-width (bins)
PEAK_LEVEL = 0.95;    % signal peak at this percentile

%% Bandpass filter to annotation band
% This is the key adaptation for bioacoustics: operating on band-limited
% energy rather than full-spectrum energy.
filterOrder = max(48, round(10 * sampleRate / diff(freq)));
filterOrder = filterOrder + mod(filterOrder, 2);
try
    d = designfilt('bandpassfir', 'FilterOrder', filterOrder, ...
        'CutoffFrequency1', freq(1), 'CutoffFrequency2', freq(2), ...
        'SampleRate', sampleRate);
    sigFiltered   = filtfilt(d, sigAudio);
    noiseFiltered = filtfilt(d, noiseAudio);
catch
    % Filter failed (e.g. freq above Nyquist) — use unfiltered
    sigFiltered   = sigAudio;
    noiseFiltered = noiseAudio;
end

%% Calibration
% Apply flat-band calibration factor at band centre frequency.
% (Frequency-dependent calibration is not straightforward for time-domain
% frame energies; use scalar gain at centre frequency as approximation.)
calFactor2 = 1;   % power scale factor (1 = no calibration)
if ~isempty(metadata)
    centreFq   = mean(freq);
    gainAtCentre = interp1(log10(metadata.frontEndFreq_Hz), ...
        metadata.frontEndGain_dB, log10(centreFq), 'linear', 'extrap');
    calFactor  = metadata.adPeakVolt / 10^((metadata.hydroSensitivity_dB + gainAtCentre) / 20);
    calFactor2 = calFactor^2;
end

%% Frame energy histogram on combined (signal + noise) audio
% Pool signal and noise windows to build a histogram representing both
% the quiet (noise) and active (signal) states of the recording.
combined = [noiseFiltered; sigFiltered];

frameWidth = round(FRAME_MS / 1000 * sampleRate);
frameAdv   = max(1, round(frameWidth / 2));  % stnr.txt: frame_adv = frame_width/2

% Guard: require at least 10 frames from the signal window alone.
% Checking the combined length is wrong — a tiny signal appended to a
% long noise window still yields thousands of frames from the noise half,
% making the histogram uninformative about the actual signal.
if floor(length(sigFiltered) / frameAdv) < 10
    rmsSignal = mean(sigFiltered.^2)   * calFactor2;
    rmsNoise  = mean(noiseFiltered.^2) * calFactor2;
    noiseVar  = var(noiseFiltered.^2)  * calFactor2^2;
    histogramData  = struct();
    return
end

% Frame power in dB (with 16384 scaling matching original NIST tool).
% Following stnr.txt algorithm:
%   D2     = (D * 16384).^2           squared scaled samples
%   P2     = mean over each half-window
%   Pdb    = 10*log10(conv([1 1], P2)) — sums adjacent half-windows to give
%            overlapping full-window power (the NIST 'conv trick').
% Using 10*log10 (power dB), not 20*log10 (amplitude dB).
D2scaled = (combined * 16384).^2;
nHops    = floor(length(D2scaled) / frameAdv);
D2mat    = reshape(D2scaled(1 : nHops * frameAdv), frameAdv, nHops);
P2       = mean(D2mat, 1);                  % mean power per half-window
Pfull    = conv([1 1], P2);                 % sum adjacent half-windows
Pfull    = Pfull(1 : nHops);               % trim back to nHops entries
Pfull    = max(Pfull, eps);                % guard against log(0)
frameEnergy_dB = 10 * log10(Pfull);
frameEnergy_dB = max(LOW_dB, min(HIGH_dB, frameEnergy_dB));

%% Build and smooth histogram
binEdges   = linspace(LOW_dB, HIGH_dB, BINS + 1);
binCentres = (binEdges(1:end-1) + binEdges(2:end)) / 2;
histo      = histcounts(frameEnergy_dB, binEdges);

% Step 1: median despike (width 3) — stnr.txt: medianf(power_hist, 3).
% Removes single-bin impulse artefacts before smoothing.
histRaw    = double(histo);
unspiked   = medfilt1(histRaw, 3);

% Step 2: rectangular smoothing (SMOOTH_BINS = 15) — equivalent to NIST smooth.
kernel     = ones(1, SMOOTH_BINS) / SMOOTH_BINS;
histSmooth = conv(unspiked, kernel, 'same');

%% Find noise peak (leftmost significant local maximum in histogram)
% The noise occupies the low-energy left side of the histogram.
% Search the FULL histogram for the leftmost local maximum that rises above
% a significance threshold (5 % of the global peak count). Restricting to
% the first half of the bin range is incorrect: for typical audio (e.g.
% noiseRMS ~ 0.1 full-scale), the 16384-scaled frame energies map to
% 50–80 dB in the NIST internal dB scale, well above the mid-point
% (~34 dB) of the 500-bin range spanning -28 to +97 dB.
%
% Bioacoustic adaptation: use the leftmost significant peak rather than
% the global maximum (stnr.txt uses global max), so that a tall signal
% peak at high SNR does not displace the noise estimate.
sigThreshold = max(histSmooth) * 0.05;   % 5 % of global peak
localMax     = (histSmooth(2:end-1) >= histSmooth(1:end-2)) & ...
               (histSmooth(2:end-1) >= histSmooth(3:end))   & ...
               (histSmooth(2:end-1) >= sigThreshold);
peakBins     = find(localMax) + 1;       % offset: localMax index 1 = bin 2
if isempty(peakBins)
    % Fallback: global maximum (stnr.txt algorithm)
    [~, noisePeakBin] = max(histSmooth);
else
    noisePeakBin = peakBins(1);           % leftmost significant peak
end

noisedB = binCentres(noisePeakBin);

% Raised cosine fit: find half-width at half-maximum of noise peak
halfMax = histSmooth(noisePeakBin) / 2;
leftBin  = find(histSmooth(1:noisePeakBin) <= halfMax, 1, 'last');
rightBin = noisePeakBin + find(histSmooth(noisePeakBin:end) <= halfMax, 1, 'first') - 1;
if isempty(leftBin),  leftBin  = 1; end
if isempty(rightBin), rightBin = noisePeakBin + 1; end
noiseWidth_dB = (binCentres(rightBin) - binCentres(leftBin)) / 2;
noiseWidth_dB = max(noiseWidth_dB, 1);   % at least 1 dB

%% Find signal peak at PEAK_LEVEL percentile of cumulative histogram
cumHist       = cumsum(histSmooth) / sum(histSmooth);
signalBin     = find(cumHist >= PEAK_LEVEL, 1, 'first');
if isempty(signalBin), signalBin = BINS; end
signaldB      = binCentres(signalBin);

%% Convert dB energy estimates to linear power
% The histogram stores 10*log10(Pfull) where Pfull = P2(i) + P2(i+1),
% the SUM of two adjacent half-window mean powers (the stnr.txt conv trick).
% For a stationary signal Pfull ≈ 2 × true_frame_power, so absolute
% levels are ~3 dB (power) / ~1.5 dB (amplitude) higher than true RMS.
% This offset cancels in the SNR ratio (both estimates share the same
% Pfull scale), so SNR is unbiased.  Absolute levels are reported in the
% NIST internal scale; use with calibration if physical units are needed.
%
% Conversion: power = 10^(dB/10) / 16384^2
%   equivalently: amplitude_rms = 10^(dB/20) / 16384  => power = amplitude_rms^2
scale = 16384;
noiseRMS_raw  = 10^(noisedB  / 20) / scale;
signalRMS_raw = 10^(signaldB / 20) / scale;

rmsNoise  = noiseRMS_raw^2  * calFactor2;
rmsSignal = signalRMS_raw^2 * calFactor2;

%% noiseVar from noise-window frame energies (same NIST framing as histogram)
% Use the identical conv-based overlapping-window framing so that noiseVar
% is on the same power scale as rmsNoise (both derived from Pfull units).
nNoiseHops = floor(length(noiseFiltered) / frameAdv);
if nNoiseHops >= 2
    D2noise    = (noiseFiltered(1 : nNoiseHops * frameAdv) * 16384).^2;
    D2nMat     = reshape(D2noise, frameAdv, nNoiseHops);
    P2noise    = mean(D2nMat, 1);
    PfullNoise = conv([1 1], P2noise);
    PfullNoise = PfullNoise(1 : nNoiseHops);
    PfullNoise = max(PfullNoise, eps);
    % Convert to calibrated linear power (same scale as rmsNoise)
    noiseFrameEnergy = (PfullNoise / 16384^2) * calFactor2;
    noiseVar = var(noiseFrameEnergy);
else
    noiseVar = 0;
end

%% Diagnostic data for plotting
histogramData.binCentres    = binCentres;
histogramData.histSmooth    = histSmooth;
histogramData.histRaw       = histRaw;        % pre-smoothing counts
histogramData.noisedB       = noisedB;
histogramData.signaldB      = signaldB;
histogramData.noiseWidth_dB = noiseWidth_dB;
histogramData.noisePeakBin  = noisePeakBin;  % for test inspection

end
