# bsnr — Roadmap and Todo

bsnr is a working tool in active use, not a finished standard. This file tracks planned features, known issues, and future work.

---

## Planned features

### `snrType = 'spectrogramSlicesTrimmed'`
Trim signal window to the central 95% of energy in both time (drop low-energy leading/trailing slices) and frequency (drop low-energy edge PSD bins), then apply identical trim to the noise window. Only active when per-annotation frequency bounds are used — has no effect with fixed frequency bands. Intended to standardise SNR estimates across analysts with different annotation box tightness. Not a defence against non-stationary noise, but no worse than untrimmed.

### `resultTable` and `resolvedParams` outputs from `snrEstimate`
Return a structured results table and the resolved parameter set (including derived nfft) as additional outputs from `snrEstimate`, to improve reproducibility and downstream processing.

### ASA passive acoustic metadata alignment
Align `snrEstimate` inputs and outputs with the ASA specification for passive acoustic metadata (detections, recordings, and output), to improve interoperability with PAMGuard, Raven Pro, and related tools.

---

## Pending documentation

### Common Ground example (`snr_abw_casey2019_commonground.m`)
Add to `docs/index.html` and `examples/publishDocs.m` once Miller et al. (in press, *Methods in Ecology and Evolution*) is published.

---

## Low priority / future

- `writeBsnrResults()` — CSV + XML writer for SNR results
- AADC metadata record for Casey 2019 data subset (downsampled FLAC)
- Port to R. Best package name: `BSnR` (self-deprecating; not a jab at R).
  Alternatively: `bsnr` in R, which works fine without the capitalisation joke.
