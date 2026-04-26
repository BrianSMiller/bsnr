# bsnr — Roadmap and Todo

bsnr is a working tool in active use, not a finished standard. This file tracks planned features, known issues, and future work.

---

## Planned features

### Parallel processing for `trimAnnotation`
`trimAnnotation` currently runs serially. Add `parfor` support matching
`snrEstimate`'s parallel threshold logic.

### Auto-trim algorithms
Investigate automated methods for tightening annotation boxes beyond the
current energy percentile approach — e.g. onset/offset detection, adaptive
thresholding, or spectrogram-based segmentation.

### Auto-segmentation of signal and noise
Algorithms for separating signal and noise regions without manual annotation
boxes. Reference: Hory, Martin & Chehikian (2002), "Spectrogram segmentation
by means of statistical features for non-stationary signal interpretation."
IEEE Trans. Signal Processing 50(12), 2915–2925.

### Smooth ridge and synchrosqueeze pitch tracks
Apply smoothing to the instantaneous frequency estimates from `snrRidge` and
`snrSynchrosqueeze` to reduce jitter. Candidate approaches: LOESS, GAM,
spline, or polynomial fits. Smoothed track would be stored in
`methodData.ridgeFreqSmooth` alongside the raw track.

### Makara output (`writeMakaraDetections`)
NOAA is developing Makara as a US-centric successor to Tethys, using CSV
templates. Add `writeMakaraDetections()` once the format stabilises (tracked
at NOAA Fisheries passive acoustics). Currently `writeTethysXml` covers the
NCEI submission path.

### ASA passive acoustic metadata alignment
Align `snrEstimate` inputs and outputs with the ASA specification for passive
acoustic metadata (detections, recordings, and output), to improve
interoperability with PAMGuard, Raven Pro, and related tools.

### `writeBsnrResults()` — CSV + XML writer
Write bsnr result tables to CSV and/or XML with full provenance
(resolvedParams, software version, datetime).

### AADC metadata record
Formal AADC metadata record for the Casey 2019 data subset used in the
published-data examples (downsampled FLAC).

---

## Pending documentation

### Common Ground example (`snr_abw_casey2019_commonground.m`)
Add to `docs/index.html` and `examples/publishDocs.m` once Miller et al.
(in press, *Methods in Ecology and Evolution*) is published.

---

## Longer term

### Port to R (`BSnR`)
Best package name: `BSnR` (self-deprecating; not a jab at R). Alternatively
`bsnr` in R, which works fine without the capitalisation joke.
