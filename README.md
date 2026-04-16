# bsnr — Bioacoustic SNR Estimation

MATLAB toolbox for estimating signal-to-noise ratio of bioacoustic detections from hydrophone recordings. Designed for tonal and frequency-modulated calls (whale song, upcalls, clicks) against broadband ocean noise.

## Features

- **Seven SNR methods** spanning bioacoustic, speech, and engineering approaches
- **Calibrated acoustic levels** (dB re 1 µPa) from instrument metadata
- **Spectrogram visualisation** with signal/noise window overlays and quantile contours
- **Click removal** for recordings with impulsive interference
- **Three display types** per method — spectrogram, time series, or histogram
- **Batch processing** with optional parallel execution, with warnings when STFT parameters would produce non-comparable results across annotations
- **Comprehensive test suite** with synthetic fixtures

## SNR Methods

| Method | `snrType` | Best for | Notes |
|--------|-----------|----------|-------|
| Spectrogram | `'spectrogram'` | Broadband tonal | Mean band PSD; simple or Lurton formula |
| Spectrogram slices | `'spectrogramSlices'` | Broadband tonal | Per-slice band power |
| Time domain | `'timeDomain'` | Any bandwidth | Bandpass FIR, mean instantaneous power |
| Ridge | `'ridge'` | FM tonal | `tfridge` dominant ridge; per-bin SNR |
| Synchrosqueeze | `'synchrosqueeze'` | FM tonal | FSST ridge, sharper TF localisation; per-bin SNR |
| Quantiles | `'quantiles'` | Tonal (no noise window needed) | Within-window 85th/15th percentile split |
| NIST histogram | `'nist'` | Any | Frame energy histogram; Ellis (2011); bandpass-filtered to annotation band |

The simple power ratio and Lurton formula are both available for all methods via `params.useLurton`. Ridge and synchrosqueeze report per-bin SNR, which exceeds band-average SNR by ~10·log10(nBandBins) and is not directly comparable to the other methods.

## Quick Start

```matlab
% Add bsnr and dependencies to path
addpath('C:\analysis\bsnr', '-begin');
addpath('C:\analysis\soundFolder');        % wavFolderInfo, getAudioFromFiles
addpath('C:\analysis\annotatedLibrary');   % annotation utilities
addpath('C:\analysis\soundFolder');         % sound folder utilities

% Define a detection annotation
annot.soundFolder    = 'D:\recordings\site1';
annot.t0             = datenum([2024 03 15 10 30 00]);
annot.tEnd           = datenum([2024 03 15 10 30 02]);
annot.duration       = 2;
annot.freq           = [80 120];   % Hz
annot.channel        = 1;

% Estimate SNR (spectrogram method, default beforeAndAfter noise window)
snr = snrEstimate(annot);
fprintf('SNR = %.1f dB\n', snr);

% Show spectrogram with signal/noise overlays
params.showClips      = true;
params.pauseAfterPlot = false;
snr = snrEstimate(annot, params);

% Lurton formula with histogram display
params.useLurton   = true;
params.displayType = 'histogram';
snr = snrEstimate(annot, params);
```

## STFT Parameters

`params.nfft` and `params.nOverlap` are the primary parameters for all spectrogram-based methods. When not set, they are derived from `params.nSlices` (default 30) and the annotation duration.

**For batch processing, always set `params.nfft` explicitly.** A constant `nfft` across all annotations is required for SNR values to be comparable. When `nfft` is not set in batch mode, bsnr derives it from the median annotation duration and issues a warning.

```matlab
params.nfft     = 512;   % FFT length (samples)
params.nOverlap = 384;   % overlap (samples); default floor(nfft * 0.75)
```

## Display Types

Each method supports up to three display types, selected via `params.displayType`:

```matlab
params.displayType = 'spectrogram';  % TF spectrogram with signal/noise overlays (default)
params.displayType = 'timeSeries';   % per-slice band power vs time
params.displayType = 'histogram';    % signal and noise slice power distributions
```

The `timeDomain` method uses `plotBandSamplePower` (per-sample FIR-filtered power) for `'timeSeries'`; all other methods use per-STFT-slice band power.

## Calibrated Levels

When `params.metadata` is provided, the output table includes:

- `signalBandLevel_dBuPa` — band-integrated signal level (dB re 1 µPa)
- `noiseBandLevel_dBuPa` — band-integrated noise level (dB re 1 µPa)

These are equivalent to `bandpower(psdCal, f, freq, 'psd')` from a calibrated PSD, and are correct for both tonal and broadband signals.

```matlab
metadata.hydroSensitivity_dB   % dB re V/µPa
metadata.adPeakVolt            % ADC peak voltage (V)
metadata.frontEndFreq_Hz       % frequency axis for gain curve
metadata.frontEndGain_dB       % frontend gain at each frequency (dB)
```

## Noise Window

By default, noise is measured symmetrically around the detection with a 0.5 s gap (`noiseDelay = 0.5`). Common alternatives:

```matlab
% Noise before detection only, 1 s gap
params.noiseDuration = 'before';
params.noiseDelay    = 1.0;

% 25 s window before detection (long-term noise estimate)
params.noiseDuration = '25sBefore';
```

## References

Simple power ratio (`snrType='spectrogram'`, `useLurton=false`):

> Miller et al. (2022). Deep Learning Algorithm Outperforms Experienced Human Observer at Detection of Blue Whale D-calls. *Remote Sensing in Ecology and Conservation*. https://doi.org/10.1002/rse2.297

> Castro et al. (2024). Beyond Counting Calls: Estimating Detection Probability for Antarctic Blue Whales. *Frontiers in Marine Science*. https://doi.org/10.3389/fmars.2024.1406678

Lurton formula (`useLurton=true`):

> Miller et al. (2021). An Open Access Dataset for Developing Automated Detectors of Antarctic Baleen Whale Sounds. *Scientific Reports* 11, 806. https://doi.org/10.1038/s41598-020-78995-8

NIST STNR histogram method (`snrType='nist'`):

> Ellis, D.P.W. (2011). nist_stnr_m.m. LabROSA/Columbia University. https://labrosa.ee.columbia.edu/~dpwe/tmp/nist/doc/stnr.txt

## Examples

See `examples/bsnr_gallery.m` for illustrated examples covering all methods, display types, calibrated levels, click removal, and real Antarctic baleen whale recordings.

```matlab
cd C:\analysis\bsnr\examples
publish('bsnr_gallery.m', 'format', 'html', 'outputDir', '..\docs')
movefile('..\docs\bsnr_gallery.html', '..\docs\index.html')
```

## Running Tests

```matlab
run('C:\analysis\bsnr\tests\run_tests.m')
```

The test suite covers unit tests for each SNR method, full-pipeline integration tests, calibration chain verification, noise window placement strategies, edge cases, and visual inspection plots.

## Dependencies

- MATLAB R2021b or later
- Signal Processing Toolbox (`designfilt`, `filtfilt`, `tfridge`, `fsst`)
- [longTermRecorders](https://github.com/aaad) — `wavFolderInfo`, `getAudioFromFiles`
- [soundFolder](https://github.com/BrianSMiller/soundFolder) — `wavFolderInfo`, `getAudioFromFiles`
- [annotatedLibrary](https://github.com/BrianSMiller/annotatedLibrary) — annotation utilities

## File Structure

```
bsnr/
├── README.md
├── bsnr.m                       Help/doc entry point
├── snrEstimate.m                Main entry point (scalar and batch)
├── snrSpectrogram.m             Spectrogram method
├── snrSpectrogramSlices.m       Per-slice spectrogram method
├── snrTimeDomain.m              Time-domain bandpass method
├── snrRidge.m                   Ridge tracking method
├── snrSynchrosqueeze.m          Synchrosqueezing method
├── snrQuantiles.m               Within-window quantile method
├── snrHistogram.m               Frame energy histogram (NIST STNR)
├── spectroAnnotationAndNoise.m  Spectrogram display with overlays
├── plotBandSamplePower.m        Per-sample bandpass power display (timeDomain)
├── removeClicks.m               Impulsive noise suppression
├── validate_dcalls_miller2022.m Validation script (Miller et al. 2022)
├── private/
│   ├── colorbarFixTickLabel.m   Colorbar tick label decorator (≤/≥ for clipped ranges)
│   ├── plotBandHistogram.m      Unified signal/noise slice power histogram
│   ├── plotBandSlicePower.m     Per-slice band power time series
│   ├── plotHistogramSNR.m       NIST frame energy histogram
│   ├── plotLurtonHistogram.m    Lurton histogram wrapper
│   ├── plotQuantilesHistogram.m Quantiles TF cell histogram
│   └── resolveDisplayType.m     Display type selection logic
├── experimental/
│   └── snrWADA.m                WADA-SNR (Kim & Stern 2008; not yet integrated)
├── examples/
│   ├── bsnr_gallery.m           Publishable gallery of examples
│   ├── simpleFlatMetadata.m     Flat-response instrument metadata example
│   └── prepareGalleryAudio.m    Extract gallery audio clips from library
└── tests/
    ├── run_tests.m                   Test suite driver
    ├── test_snrMethods.m             Unit tests for all SNR methods
    ├── test_removeClicks.m           Click removal tests
    ├── test_snrEstimate_scalar.m     Integration tests (scalar)
    ├── test_snrEstimate_batch.m      Batch processing tests
    ├── test_snrEstimate_noiseWindows.m  Noise window strategy tests
    ├── test_calibration.m            Calibration chain verification
    ├── test_plots.m                  Visual inspection figures
    ├── createTestFixture.m           Synthetic WAV fixture generator
    ├── createCalibratedTestFixture.m Calibrated fixture generator
    ├── makeSyntheticAudio.m          Audio array generator (tone-in-noise)
    ├── makeSRWUpcall.m               SRW FM upcall generator
    └── makeClickAudio.m              Click-contaminated audio generator
```

## Licence

Copyright © Australian Antarctic Division. See LICENCE for details.
