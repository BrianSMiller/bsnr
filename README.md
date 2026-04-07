# bsnr — Bioacoustic SNR Estimation

MATLAB toolbox for estimating signal-to-noise ratio of bioacoustic detections from hydrophone recordings. Designed for tonal and frequency-modulated calls (whale song, upcalls, clicks) against broadband ocean noise.

## Features

- **Seven SNR methods** spanning bioacoustic, speech, and engineering approaches
- **Calibrated acoustic levels** (dB re 1 µPa) from instrument metadata
- **Spectrogram visualisation** with signal/noise window overlays and quantile contours
- **Click removal** for recordings with impulsive interference
- **Batch processing** with optional parallel execution
- **Comprehensive test suite** with synthetic fixtures

## SNR Methods

| Method | `snrType` | Best for | Notes |
|--------|-----------|----------|-------|
| Spectrogram | `'spectrogram'` | Broadband tonal | Mean band PSD; simple or Lurton formula |
| Spectrogram slices | `'spectrogramSlices'` | Broadband tonal | Per-slice band power median |
| Time domain | `'timeDomain'` | Any bandwidth | Bandpass FIR, mean instantaneous power |
| Ridge | `'ridge'` | FM tonal | tfridge dominant ridge |
| Synchrosqueeze | `'synchrosqueeze'` | FM tonal | FSST ridge, sharper TF localisation |
| Quantiles | `'quantiles'` | Tonal (no noise window) | Within-window 85th/15th percentile |
| NIST histogram | `'nist'` | Any | Frame energy histogram; Ellis (2011); bandpass-filtered to annotation band |

The simple power ratio and Lurton formula are both available for spectrogram, spectrogramSlices, timeDomain, ridge, and synchrosqueeze methods via `params.useLurton`.

## Quick Start

```matlab
% Add bsnr and dependencies to path
addpath('C:\analysis\bsnr', '-begin');
addpath('C:\analysis\longTermRecorders');   % wavFolderInfo, getAudioFromFiles
addpath('C:\analysis\annotatedLibrary');    % doTimespansOverlap
addpath('C:\analysis\bsmTools');            % miscellaneous tools
addpath('C:\analysis\soundFolder');         % sound folder utilities

% Define a detection annotation
annot.soundFolder    = 'D:\recordings\site1';
annot.t0             = datenum([2024 03 15 10 30 00]);
annot.tEnd           = datenum([2024 03 15 10 30 02]);
annot.duration       = 2;
annot.freq           = [80 120];   % Hz
annot.channel        = 1;

% Estimate SNR (spectrogram method, 0.5 s gap between signal and noise)
[snr, rmsSignal, rmsNoise] = snrEstimate(annot);
fprintf('SNR = %.1f dB\n', snr);

% Lurton formula
params.useLurton = true;
[snrL] = snrEstimate(annot, params);
```

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
metadata.sampleRate            % sample rate (Hz)
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

See `examples/bsnr_gallery.m` for illustrated examples covering all methods, FM calls, calibrated levels, and click removal.

```matlab
cd C:\analysis\bsnr\examples
publish('bsnr_gallery.m', 'format', 'pdf', 'outputDir', '.\')
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
- [annotatedLibrary](https://github.com/aaad) — `doTimespansOverlap`
- bsmTools — miscellaneous signal processing utilities
- soundFolder — sound folder management

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
├── plotTimeDomainPower.m        Time-domain power display
├── removeClicks.m               Impulsive noise suppression
├── validate_dcalls_miller2022.m Validation script (Miller et al. 2022)
├── private/
│   └── plotHistogramSNR.m       NIST histogram diagnostic plot (internal)
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
