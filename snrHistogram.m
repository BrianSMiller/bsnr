function [rmsSignal, rmsNoise, noiseVar] = snrNIST( ...
    sigAudio, noiseAudio, nfft, nOverlap, sampleRate, freq, metadata)
% Estimate SNR using the NIST STNR 'quick' method (stnr -c algorithm).
%
% The NIST STNR algorithm constructs a histogram of short-time frame
% energies (20 ms windows, 10 ms advance), fits a raised cosine to the
% left-hand (noise) peak, and locates signal energy at the 95th percentile.
% SNR = 20*log10(signal_std / noise_std).
%
% Originally designed for speech SNR estimation (Ellis 2011, LabROSA).
% Adapted here for bioacoustics by bandpass filtering to freq before
% computing frame energies, so the histogram reflects energy within the
% annotation frequency band rather than the full spectrum.
%
% Reference:
%   Ellis, D.P.W. (2011). nist_stnr_m.m. LabROSA/Columbia University.
%   https://labrosa.ee.columbia.edu/~dpwe/tmp/nist/doc/stnr.txt
%   (NIST does not endorse this method.)
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

if nargin < 7, metadata = []; end

%% Constants (from nist_stnr_m.m / snr.h)
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
frameAdv   = max(1, floor(frameWidth / 2));
nFrames    = floor(length(combined) / frameAdv);
if nFrames < 10
    % Too short — fall back to RMS ratio
    rmsSignal = mean(sigFiltered.^2)   * calFactor2;
    rmsNoise  = mean(noiseFiltered.^2) * calFactor2;
    noiseVar  = var(noiseFiltered.^2)  * calFactor2^2;
    return
end

% Frame RMS in dB (with 16384 scaling matching original NIST tool)
frameEnergy_dB = zeros(1, nFrames);
for k = 1:nFrames
    idx = (k-1)*frameAdv + (1:frameAdv);
    idx = idx(idx <= length(combined));
    if ~isempty(idx)
        rmsFrame = sqrt(mean((combined(idx) * 16384).^2));
        if rmsFrame > 0
            frameEnergy_dB(k) = 20 * log10(rmsFrame);
        else
            frameEnergy_dB(k) = LOW_dB;
        end
    end
end
frameEnergy_dB = max(LOW_dB, min(HIGH_dB, frameEnergy_dB));

%% Build and smooth histogram
binEdges  = linspace(LOW_dB, HIGH_dB, BINS + 1);
binCentres = (binEdges(1:end-1) + binEdges(2:end)) / 2;
histo     = histcounts(frameEnergy_dB, binEdges);

% Rectangular smoothing (equivalent to NIST SMOOTH_BINS)
kernel    = ones(1, SMOOTH_BINS) / SMOOTH_BINS;
histSmooth = conv(double(histo), kernel, 'same');

%% Find noise peak (leftmost significant peak in histogram)
% The noise occupies the low-energy left side of the histogram.
% Find the first local maximum, then fit a raised cosine to it.
[~, noisePeakBin] = max(histSmooth(1:round(BINS/2)));

% Estimate noise std as the bin centre at the noise peak
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
% The histogram is in dB of RMS amplitude scaled by 16384.
% Convert back: remove the 16384 scaling and recover power.
scale = 16384;
noiseRMS_raw  = 10^(noisedB  / 20) / scale;
signalRMS_raw = 10^(signaldB / 20) / scale;

rmsNoise  = noiseRMS_raw^2  * calFactor2;
rmsSignal = signalRMS_raw^2 * calFactor2;

%% noiseVar from noise window frame energies
noiseFrameEnergy = zeros(1, floor(length(noiseFiltered) / frameAdv));
for k = 1:length(noiseFrameEnergy)
    idx = (k-1)*frameAdv + (1:frameAdv);
    idx = idx(idx <= length(noiseFiltered));
    if ~isempty(idx)
        noiseFrameEnergy(k) = mean((noiseFiltered(idx) * calFactor2^0.5).^2);
    end
end
noiseVar = var(noiseFrameEnergy);

end
