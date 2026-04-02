# bsnr — Bioacoustic SNR Estimation

MATLAB toolbox for estimating signal-to-noise ratio of bioacoustic detections from hydrophone recordings. Designed for tonal and frequency-modulated calls (whale song, upcalls, clicks) against broadband ocean noise.

## Features

- **Six SNR methods** covering broadband, tonal, and FM signals
- **Calibrated acoustic levels** (dB re 1 µPa) from instrument metadata
- **Spectrogram visualisation** with signal/noise window overlays
- **Click removal** for recordings with impulsive interference
- **Batch processing** with optional parallel execution
- **Comprehensive test suite** with synthetic fixtures

## SNR Methods

| Method | Best for | Notes |
|--------|----------|-------|
| `spectrogram` | Broadband tonal | Mean band PSD, robust to non-stationarity |
| `spectrogramSlices` | Broadband tonal | Per-slice band power (Miller et al. 2021) |
| `timeDomain` | Any bandwidth | Bandpass FIR, mean instantaneous power; calibrated absolute levels |
| `ridge` | FM tonal | tfridge dominant ridge, handles upcalls/downsweeps |
| `synchrosqueeze` | FM tonal | Fourier synchrosqueezed transform, sharper TF localisation |
| `spectrogram (Lurton)` | High SNR | Lurton (2002): 10·log₁₀((S−N)²/σ²_N) |

## Quick Start

```matlab
% Add bsnr and dependencies to path
addpath('C:\analysis\bsnr');
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

% Estimate SNR (spectrogram method)
params = struct('snrType', 'spectrogram');
[snr, rmsSignal, rmsNoise] = snrEstimate(annot, params);
fprintf('SNR = %.1f dB\n', snr);

% With calibration metadata
params.metadata = metaDataKerguelen2024;
[resultTable] = snrEstimate(annot, params);
fprintf('Signal band level = %.1f dB re 1 µPa\n', resultTable.signalBandLevel_dBuPa);
```

## Calibrated Levels

When `params.metadata` is provided, the output table includes:

- `signalBandLevel_dBuPa` — band-integrated signal level (dB re 1 µPa)
- `noiseBandLevel_dBuPa` — band-integrated noise level (dB re 1 µPa)

These are equivalent to `bandpower(psdCal, f, freq, 'psd')` from a calibrated PSD, and are correct for both tonal and broadband signals.

The metadata struct requires:

```matlab
metadata.hydroSensitivity_dB   % dB re V/µPa
metadata.adPeakVolt            % ADC peak voltage (V)
metadata.frontEndFreq_Hz       % frequency axis for gain curve
metadata.frontEndGain_dB       % frontend gain at each frequency (dB)
metadata.sampleRate            % sample rate (Hz)
```

## Examples

See the [gallery](examples/html/bsnr_gallery.html) for illustrated examples covering all methods, FM calls, calibrated levels, and click removal.

To regenerate the gallery HTML:

```matlab
cd C:\analysis\bsnr\examples
publish('bsnr_gallery.m', 'format', 'html', 'outputDir', 'html')
```

## Running Tests

```matlab
run('C:\analysis\bsnr\tests\run_tests.m')
```

The test suite covers unit tests for each SNR method, integration tests through the full `snrEstimate` pipeline, calibration verification against known acoustic levels, and click removal.

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
├── snrEstimate.m          Main entry point (scalar and batch)
├── snrSpectrogram.m         Spectrogram method
├── snrSpectrogramSlices.m   Per-slice spectrogram method
├── snrTimeDomain.m          Time-domain bandpass method
├── snrRidge.m               Ridge tracking method
├── snrSynchrosqueeze.m      Synchrosqueezing method
├── snrQuantiles.m           Quantile method (experimental)
├── spectroAnnotationAndNoise.m   Spectrogram display
├── plotTimeDomainPower.m    Time-domain power display
├── removeClicks.m           Impulsive noise suppression
├── examples/
│   ├── bsnr_gallery.m       Publishable gallery of examples
│   ├── simpleFlatMetadata.m Flat-response instrument metadata
│   └── html/                Generated HTML gallery (after publish)
└── tests/
    ├── run_tests.m           Test suite driver
    ├── test_snrMethods.m     Unit tests for SNR methods
    ├── test_removeClicks.m   Click removal tests
    ├── test_snrEstimate_scalar.m   Integration tests
    ├── test_snrEstimate_batch.m    Batch processing tests
    ├── test_calibration.m    Calibration chain verification
    ├── test_plots.m          Visual inspection plots
    ├── createTestFixture.m   Synthetic WAV fixture generator
    ├── createCalibratedTestFixture.m  Calibrated fixture
    ├── makeSyntheticAudio.m  Audio array generator
    ├── makeSRWUpcall.m       SRW upcall generator
    └── makeClickAudio.m      Click-contaminated audio
```

## Citation

If you use bsnr in your research, please cite:

> Miller, B.S. et al. (2021). Estimating the detection range of a tonal
> bioacoustic signal using a spectrogram-based SNR estimator.
> *Journal of the Acoustical Society of America.*

## Licence

Copyright © Australian Antarctic Division. See LICENCE for details.
