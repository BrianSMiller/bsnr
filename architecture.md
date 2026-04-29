# bsnr — Architecture

This document describes the structure of the bsnr codebase: what each file
does, how the pieces fit together, and the key design decisions that shaped
the current architecture. It is intended as a quick-start reference for
development sessions and for anyone reading the code for the first time.

---

## Design philosophy

Three principles, in order of priority:

1. **Correct** — results match the underlying physics and the published methods
   they implement. Calibration is applied consistently. SNR formulas are
   documented and testable against known inputs.

2. **Clear** — code reads like the methods section of a paper. Function names
   match the concepts they implement. Parameters have explicit defaults and
   documented units.

3. **Consistent** — all SNR methods share the same input/output interface.
   Parallel processing, calibration, and plotting work the same way across
   all methods.

---

## Repository layout

```
bsnr/
├── bsnr.m                          Main entry point / help file
├── snrEstimate.m                   Public API — thin wrapper
├── trimAnnotation.m                Annotation trimming
├── removeClicks.m                  Click suppression
├── readTethysDetections.m          Tethys XML → annotation table
├── writeTethysXml.m                Annotation table → Tethys XML
├── run_tests.m                     Test runner
├── README.md
├── architecture.md                 This file
├── todo.md                         Roadmap and known issues
├── .gitignore
│
├── private/                        Implementation details (not on MATLAB path)
│   ├── snrEstimateImpl.m           Core estimation logic + batch dispatch
│   ├── snrSpectrogram.m            Method: mean band power
│   ├── snrSpectrogramSlices.m      Method: per-slice band power
│   ├── snrTimeDomain.m             Method: RMS in time domain
│   ├── snrRidge.m                  Method: spectral ridge tracking
│   ├── snrSynchrosqueeze.m         Method: synchrosqueezed transform ridge
│   ├── snrHistogram.m              Method: NIST histogram
│   ├── snrQuantiles.m              Method: quantile-based noise floor
│   ├── applyCalibration.m          Apply hydrophone calibration to PSD
│   ├── resolveDisplayType.m        Map snrType → plot function
│   ├── plotTrimDiagnostic.m        trimAnnotation diagnostic figure
│   ├── plotBandHistogram.m         Display: band histogram
│   ├── plotBandSamplePower.m       Display: sample power
│   ├── plotBandSlicePower.m        Display: slice power
│   ├── plotHistogramSNR.m          Display: histogram SNR
│   ├── plotLurtonHistogram.m       Display: Lurton formula histogram
│   ├── plotQuantilesHistogram.m    Display: quantiles histogram
│   ├── colorbarFixTickLabel.m      Utility: colorbar formatting
│   ├── spectroAnnotationAndNoise.m Diagnostic spectrogram plot
│   ├── test_snrMethods.m           Unit tests for SNR methods (needs private/)
│   └── test_removeClicks.m         Click suppression tests
│
├── tests/                          Tests and fixtures (all need private/ on path)
│   ├── createTestFixture.m         High-level fixture builder (WAV + annotation)
│   ├── createCalibratedTestFixture.m  Calibrated fixture for absolute level tests
│   ├── makeClickAudio.m            Test fixture: clicks
│   ├── makeSRWUpcall.m             Test fixture: FM upcall (known analytic IF)
│   ├── makeSyntheticAudio.m        Test fixture: tone in noise
│   ├── test_calibration.m          Calibration pipeline tests
│   ├── test_plots.m                Visual/integration tests (all plot functions)
│   ├── test_snrEstimate_batch.m    Batch + parallel processing tests
│   ├── test_snrEstimate_correctness.m
│   ├── test_snrEstimate_methods.m
│   ├── test_snrEstimate_noiseWindows.m
│   ├── test_snrEstimate_outputs.m
│   ├── test_snrEstimate_scalar.m
│   ├── test_tethys.m               Tethys I/O round-trip tests
│   ├── test_trimAnnotation.m       trimAnnotation tests
│   ├── test_parallel_performance.m Parallel timing benchmark (manual)
│   ├── debug_calibration.m         Development utility
│   └── verify_calibration_pwelch.m Development utility
│
├── examples/                       Worked examples with real data
│   ├── bsnr_gallery.m              Synthetic examples — all methods, all features
│   ├── publishDocs.m               Runs publish() on gallery + examples → docs/
│   ├── snr_abw_casey2019_commonground.m   Common Ground paper replication
│   ├── snr_abw_kerguelen2014_castro2024.m
│   ├── snr_abw_sorp_library.m
│   ├── snr_dcalls_casey2019.m      D-call paper replication
│   ├── snr_parallel_guide_casey2019.m     Parallel processing guide
│   ├── metaDataCasey2019.m         Instrument calibration metadata
│   ├── audio/                      Short real-call WAV clips for gallery
│   │   ├── abw_a/, abw_b/, abw_d/, abw_z/   Antarctic blue whale calls
│   │   └── bp_20/, bp_40/                   Fin whale calls
│   └── *.csv                       Cached results (gitignored)
│
├── experimental/                   Exploratory scripts, not committed to API
│   ├── snr_tp_fp_analysis_casey2019.m
│   └── snrWADA.m
│
├── resources/
│   └── functionSignatures.json     Tab-completion hints for MATLAB editor
│
└── docs/                           GitHub Pages site (publishDocs output)
    ├── index.html
    ├── bsnr.css
    ├── getting_started.md
    ├── CHANGELOG.md
    ├── journey.md
    └── *.html / *.png              Published gallery + example output
```

---

## Call chain

A typical `snrEstimate` call flows as follows:

```
snrEstimate(annots, params)           [public, root]
  └── snrEstimateImpl(annots, params) [private]
        ├── processBatch()            [local function]
        │     └── processAnnotation() [local function, once per annotation]
        │           ├── getAudioFromFiles()       load signal audio
        │           ├── buildNoiseWindow()        load noise audio
        │           ├── snrSpectrogram()          \
        │           ├── snrSpectrogramSlices()     |
        │           ├── snrTimeDomain()            | dispatched by snrType
        │           ├── snrRidge()                 |
        │           ├── snrSynchrosqueeze()        |
        │           ├── snrHistogram()             |
        │           └── snrQuantiles()            /
        │           └── applyLurtonFormula()      if useLurton=true
        │           └── spectroAnnotationAndNoise() if showClips=true
        └── resolvedParams            returned as 6th output
```

For batches (`nAnnot >= parallelThreshold` and a pool is running):
`processBatch` uses `parfor` instead of `for`. No pool is started
automatically — the caller is responsible for pool lifecycle.

---

## Annotation format

All functions accept either a **table** or **struct array** with these fields:

| Field          | Type       | Description                          |
|----------------|------------|--------------------------------------|
| `soundFolder`  | char/cell  | Path to folder of WAV files          |
| `t0`           | datenum    | Detection start time                 |
| `tEnd`         | datenum    | Detection end time                   |
| `duration`     | double     | Duration in seconds                  |
| `freq`         | [lo hi]    | Frequency band in Hz                 |
| `channel`      | double     | Audio channel index (1-based)        |

`snrEstimate` always returns a **table** regardless of input type.

---

## SNR methods

| `snrType`            | Function               | Best for                        |
|----------------------|------------------------|---------------------------------|
| `spectrogram`        | snrSpectrogram         | Broadband, stationary calls     |
| `spectrogramSlices`  | snrSpectrogramSlices   | Canonical; matches Miller 2022  |
| `timeDomain`         | snrTimeDomain          | Simple, fast                    |
| `ridge`              | snrRidge               | Tonal FM calls (tight bounds)   |
| `synchrosqueeze`     | snrSynchrosqueeze      | FM calls, sharper TF resolution |
| `histogram`          | snrHistogram           | NIST broadband formula          |
| `quantiles`          | snrQuantiles           | Quantile-based noise floor      |

All methods return `[rmsSignal, rmsNoise, noiseVar, methodData]`.
`snrEstimateImpl` applies the Lurton or simple power ratio formula on top.

---

## Parallel processing

Both `snrEstimateImpl` and `trimAnnotation` use the same pattern:

```matlab
hasParallel = ~isempty(ver('parallel'));
useParfor   = ~plotFlag && hasParallel && ...
    (nItems >= params.parallelThreshold || ~isempty(gcp('nocreate')));
if useParfor && isempty(gcp('nocreate'))
    parpool('Processes', max(1, feature('numcores') - 1));
end
```

Key points:
- `plotFlag` (`showClips` or `showPlot`) always forces serial — plots need the main thread
- Pool is started automatically if threshold is exceeded and no pool exists
- If a pool is already running it is always used (no downside)
- `parallelThreshold` default is 100 for both functions

---

## Calibration

`applyCalibration(psd, f, t, metadata)` converts raw PSD (V²/Hz) to
calibrated PSD (µPa²/Hz) using:

```
PSD_µPa = PSD_V × 10^((-hydroSensitivity - frontEndGain + 20*log10(adPeakVolt)) / 10)
```

Calibration metadata structs (`metaDataCasey2019`, etc.) contain:
- `hydroSensitivity_dB` — hydrophone sensitivity (dB re V/µPa)
- `adPeakVolt` — ADC full-scale voltage
- `frontEndFreq_Hz`, `frontEndGain_dB` — frequency-dependent front-end gain

---

## Testing

Tests are split by access level:

- **`tests/`** — need `private/` access, run from repo root
- **`test_*.m` (root)** — use public API only, portable

`run_tests.m` prompts for:
- Plot tests (shows spectrograms, opens figures)
- Parallel tests (starts a parpool, takes ~30s)
- Verbose output

Test output is suppressed via `evalc` in quiet mode. Known issue: `evalc`
prevents breakpoint debugging. Workaround: call test functions directly
from the command line, or answer `y` to verbose.

Tests use synthetic audio fixtures (`createTestFixture`, `makeSRWUpcall`,
`makeSyntheticAudio`) that write real WAV files to `tempdir` and clean up
via `onCleanup`. No real recordings required for testing.

---

## Key design decisions

**SNR estimation is a pipeline, not a function.**
The most consequential early decision was to separate *how to measure power*
(the method functions in `private/`) from *what to do with those measurements*
(noise window construction, calibration, the Lurton formula, output formatting)
which lives in `snrEstimateImpl`. This means adding a new method requires only
a new `snrXxx.m` in `private/` with a standard `[rmsSignal, rmsNoise, noiseVar, methodData]`
signature — the rest of the pipeline is free. It also means calibration and
noise window logic are tested once, not seven times.

**The annotation box is both the interface and the limitation.**
Every function in bsnr accepts annotations as rectangular time-frequency boxes
`(t0, tEnd, freq[lo hi])` — the universal PAMGuard/Raven format. This made
the tool immediately useful for real datasets without format conversion, but
it is also the root cause of the ridge smoothing limitation: without tight
bounds, energy-based heuristics cannot reliably distinguish call energy from
noise. The annotation format is not wrong — it is simply the wrong level of
abstraction for FM call analysis. Contour-based detectors (silbido profundo)
operate at the right level. Bridging these two worlds is the main open
architectural question.

**Reproduction and exploration pull in opposite directions.**
bsnr began as a reproduction tool (can we recover published SNR values from
published supplemental data?) and grew into an exploration tool (what happens
if we try ridge tracking? LOESS smoothing? Tethys I/O?). These two goals
have different requirements: reproduction needs stability and exact parameter
documentation; exploration needs flexibility and tolerance for dead ends.
The current resolution — stable API in `snrEstimate`, exploratory features
in `experimental/`, honest documentation of limitations — is pragmatic but
not fully satisfying. The tension is documented rather than resolved.

**Calibration is optional but designed in.**
Every method accepts a `metadata` struct that converts raw PSD (V²/Hz) to
calibrated PSD (µPa²/Hz). Passing `[]` skips calibration and returns
dimensionless power ratios — useful for relative comparisons and testing.
This was a deliberate design choice: calibration should not be required for
the tool to be useful, but it should be present and correct when needed.
The alternative — requiring calibration always — would have made the test
suite much harder to write and the tool much less accessible.

**Tests live where they can see what they need to test.**
MATLAB's `private/` directory has unusual access semantics: functions there
are only accessible from the parent directory, not via `addpath`. This forced
a split between tests that need to call private method functions directly
(`private/test_snrMethods.m`) and tests that only use the public API
(`tests/test_snrEstimate_*.m`). The split turned out to be useful in its own
right — it mirrors the distinction between unit tests (method correctness)
and integration tests (pipeline correctness), which are genuinely different
things.

**Parallel processing follows the pool, not the threshold.**
The `parallelThreshold` parameter answers "is this batch large enough to be
worth parallelising?" — but the answer also depends on whether a pool is
already running. If one is, there is no startup cost and no reason not to
use it regardless of batch size. If there isn't, starting a pool takes 15–45
seconds and should only happen when the batch is large enough to recover that
cost. The threshold is therefore a startup gate, not an execution gate. This
distinction took longer to get right than it should have.
