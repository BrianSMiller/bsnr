# bsnr — Bioacoustic SNR Estimation

**Documentation:** https://briansmiller.github.io/bsnr

MATLAB toolbox for estimating signal-to-noise ratio of bioacoustic detections from hydrophone recordings. Designed for tonal and frequency-modulated calls (whale song, upcalls, clicks) against broadband ocean noise.

## Features

- **Seven SNR methods** spanning bioacoustic, speech, and engineering approaches
- **Three display types** per method — spectrogram, time series, or histogram
- **Calibrated acoustic levels** (dB re 1 µPa) from instrument metadata
- **Click removal** for recordings with impulsive interference
- **Batch processing** with optional parallel execution, with warnings when STFT parameters would produce non-comparable results across annotations

## SNR Methods

| Method | `snrType` | Best for | Notes |
|--------|-----------|----------|-------|
| Spectrogram | `'spectrogram'` | Broadband tonal | Mean band PSD; simple or Lurton formula |
| Spectrogram slices | `'spectrogramSlices'` | Broadband tonal | Per-slice band power |
| Time domain | `'timeDomain'` | Any bandwidth | Bandpass FIR, mean instantaneous power |
| Ridge | `'ridge'` | FM tonal | `tfridge` dominant ridge; per-bin SNR |
| Synchrosqueeze | `'synchrosqueeze'` | FM tonal | FSST ridge, sharper TF localisation; per-bin SNR |
| Quantiles | `'quantiles'` | Tonal (no noise window needed) | Within-window 85th/15th percentile split |
| NIST histogram | `'nist'` | Any | Frame energy histogram; NIST (1992) STNR |

The simple power ratio and Lurton formula are both available for all methods via `params.useLurton`. Ridge and synchrosqueeze report per-bin SNR, which exceeds band-average SNR by ~10·log10(nBandBins) and is not directly comparable to the other methods.

## Quick Start

```matlab
% Add bsnr and dependencies to path
addpath('C:\analysis\bsnr', '-begin');
addpath('C:\analysis\soundFolder');        % wavFolderInfo, getAudioFromFiles
addpath('C:\analysis\annotatedLibrary');   % annotation utilities

% Use a pre-extracted Z-call clip included in examples/audio/
audioDir = fullfile('C:\analysis\bsnr\examples\audio\abw_z');
sf = wavFolderInfo(audioDir, '', false, false);

annot.soundFolder    = audioDir;
annot.t0             = sf(1).startDate + 17/86400;  % 17 s into clip
annot.tEnd           = annot.t0 + 21/86400;          % 21 s duration
annot.duration       = 21;
annot.freq           = [17 28];   % Hz
annot.channel        = 1;
annot.classification = 'ABW Z';

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


## Calibrated Levels

When `params.metadata` is provided, the output table includes:

- `signalBandLevel_dBuPa` — band-integrated signal level (dB re 1 µPa)
- `noiseBandLevel_dBuPa` — band-integrated noise level (dB re 1 µPa)

```matlab
metadata.hydroSensitivity_dB   % dB re V/µPa
metadata.adPeakVolt            % ADC peak voltage (V)
metadata.frontEndFreq_Hz       % frequency axis for gain curve
metadata.frontEndGain_dB       % frontend gain at each frequency (dB)
```

## Noise Window

By default, noise is measured symmetrically around the detection with a 0.5 s gap. Common alternatives:

```matlab
params.noiseLocation   = 'before';   % single window before signal
params.noiseLocation_s = 25;         % 25 s window (default: annotation duration)
params.noiseDelay      = 1.0;        % gap in seconds (default 0.5)
```

## References

Simple power ratio (`snrType='spectrogram'`, `useLurton=false`):

> Miller et al. (2022). Deep Learning Algorithm Outperforms Experienced Human Observer at Detection of Blue Whale D-calls. *Remote Sensing in Ecology and Conservation*. https://doi.org/10.1002/rse2.297

> Castro et al. (2024). Beyond Counting Calls: Estimating Detection Probability for Antarctic Blue Whales. *Frontiers in Marine Science*. https://doi.org/10.3389/fmars.2024.1406678

Lurton formula (`useLurton=true`):

> Lurton, X. (2010). An Introduction to Underwater Acoustics: Principles and Applications (2nd ed.). Springer-Praxis. eq. 6.26

NIST STNR histogram method (`snrType='nist'`):

> NIST (1992). Signal-to-Noise Ratio utility (stnr). Speech Quality Assurance Package.
> https://labrosa.ee.columbia.edu/~dpwe/tmp/nist/doc/stnr.txt
>
> Also implemented independently in Raven Pro 1.6.1 as 'SNR NIST Quick' (Cornell Lab of Ornithology).
> Bioacousticians familiar with Raven's SNR measurement will find bsnr's `nist` method directly comparable.

## Examples

See `examples/bsnr_gallery.m` for illustrated examples covering all methods, display types, calibrated levels, click removal, and real Antarctic baleen whale recordings.

```matlab
cd C:\analysis\bsnr\examples
publishDocs
```

Three published-data examples demonstrate bsnr on real datasets and compare against original paper SNR values:

| Script | Dataset | Reference |
|--------|---------|-----------|
| `snr_dcalls_casey2019.m` | Antarctic blue whale D-calls, Casey 2019 | Miller et al. (2022) |
| `snr_abw_sorp_library.m` | ABW A/B/Z calls, 8 sites, IWC-SORP Annotated Library | Miller et al. (2021) |
| `snr_abw_kerguelen2014_castro2024.m` | ABW A/B/Z seasonal SNR and NL, Kerguelen 2014 | Castro et al. (2024) |

Each script documents the original paper's SNR method, explains the sources of discrepancy between the original and bsnr estimates, and provides a consistent bsnr implementation for future use.

## Running Tests

```matlab
run('C:\analysis\bsnr\tests\run_tests.m')
```


## Dependencies

- MATLAB R2021b or later
- Signal Processing Toolbox (`designfilt`, `filtfilt`, `spectrogram`, `fsst`, `tfridge`)
- [soundFolder](https://github.com/BrianSMiller/soundFolder) — `wavFolderInfo`, `getAudioFromFiles`
- [annotatedLibrary](https://github.com/BrianSMiller/annotatedLibrary) — annotation utilities

## File Structure

```
bsnr/
├── README.md
├── LICENSE
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
├── private/
│   ├── colorbarFixTickLabel.m   Colorbar tick label decorator (≤/≥ for clipped ranges)
│   ├── plotBandHistogram.m      Unified signal/noise slice power histogram
│   ├── plotBandSlicePower.m     Per-slice band power time series
│   ├── plotHistogramSNR.m       NIST frame energy histogram
│   ├── plotLurtonHistogram.m    Lurton histogram wrapper
│   ├── plotQuantilesHistogram.m Quantiles TF cell histogram
│   └── resolveDisplayType.m    Display type selection logic
├── experimental/
│   └── snrWADA.m                WADA-SNR (Kim & Stern 2008; not yet integrated)
├── examples/
│   ├── bsnr_gallery.m           Gallery of examples (publish to HTML)
│   ├── publishDocs.m            Publish all examples to docs/ for GitHub Pages
│   ├── snr_dcalls_casey2019.m   D-call SNR — Casey 2019 test dataset (Miller et al. 2022)
│   ├── snr_abw_sorp_library.m   ABW A/B/Z SNR — IWC-SORP Annotated Library (Miller et al. 2021)
│   ├── snr_abw_kerguelen2014_castro2024.m  ABW seasonal SNR/NL — Kerguelen 2014 (Castro et al. 2024)
│   ├── S4-captureHistory_casey2019MGA_vs_denseNetBmD24_judgedBSM_cut.csv
│   ├── simpleFlatMetadata.m     Flat-response instrument metadata example
│   └── prepareGalleryAudio.m    Extract gallery audio clips from library
└── tests/
    └── run_tests.m                   Test suite
```

## Roadmap

bsnr is a working tool in active use, not a finished standard. Current priorities
include a Common Ground example (Miller et al., in press, *Methods in Ecology and
Evolution*) and output table improvements for reproducibility.

Longer-term, we aim to align input and output formats with emerging standards for
passive acoustic metadata — including the ASA specification for recording and
detection metadata — to improve interoperability with PAMGuard, Raven Pro, and
other tools in the bioacoustics ecosystem.

## Acknowledgements

bsnr grew out of `annotationSNR.m`, an SNR measurement function originally
developed as part of the
[IWC-SORP Annotated Library](https://doi.org/10.26179/5e6056035c01b) project
at the Australian Antarctic Division. The toolbox design, implementation, test
suite, documentation, and published-data examples were developed with
extensive assistance from [Claude](https://claude.ai) (Anthropic), an AI
assistant.

## Licence

MIT License — Copyright © 2025 Australian Antarctic Division. See [LICENSE](LICENSE) for details.
