# Changelog

## v0.3.0-beta — 2026-04-24

Substantial API stabilisation. Establishes consistent conventions throughout.
Save v1.0.0 for after real-world deployment validation.

### Public API

- `snrEstimate` — name-value input via `arguments` block; always returns a
  result table (even for scalar input); `resolvedParams` as 6th output
- `trimAnnotation` — name-value input; NaN sentinels replace -1 in
  percentile hierarchy
- `removeClicks` — unchanged
- `readTethysDetections` — new; converts Tethys Detections XML or struct
  to bsnr annotation array
- `writeTethysXml` — new; writes bsnr result table as Tethys-compatible
  Detections XML (no Nilus/server required)

### Method standardisation

- All `snr*.m` methods now return `[rmsSignal, rmsNoise, noiseVar, methodData]`
  where `methodData` is a consistent struct with `.method`, `.sigSlicePowers`,
  `.noiseSlicePowers`, plus method-specific fields
- `snrTimeDomain`: removed unused `nfft`/`nOverlap` inputs (time-domain by design)
- `snrQuantiles`: removed `noiseAudio` input (single-window method; no noise window)
- `applyCalibration` extracted to `private/applyCalibration.m` (was duplicated 5×)

### Architecture

- `processOne` removed — `processBatch` now handles n=1 and n>1 uniformly
- `processOne` renamed `processAnnotation` (internal loop body)
- `snrEstimateImpl` moved to `private/`; `snrEstimate.m` is a thin wrapper
- `sliceDataSig`/`sliceDataNoise` helpers removed (superseded by `methodData`)
- `applyParamDefaults` removed (superseded by `arguments` block)
- `resolveDisplayType` updated for flat `methodData` structure

### Tests

- 12 test files, all passing
- Quiet by default (`evalc` suppresses pass output); verbose mode on request
- Test order: unit tests first, integration tests last
- `test_tethys` — 8 tests covering read, write, round-trip, struct input

### Docs

- `docs/getting_started.md` — installation, first estimate, annotation format,
  Tethys workflow, method selection, batch processing, calibration, troubleshooting
- Design philosophy added to `README.md`, `bsnr.m`, `docs/index.html`
- `examples/tethys_example.xml` — bundled Tethys Detections XML for gallery demo

### Compatibility

- Struct input to `snrEstimate` still supported (backward compatible)
- `datenum` and `datetime` both accepted for `t0`/`tEnd`
