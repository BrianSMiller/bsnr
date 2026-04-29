# bsnr — Roadmap and Todo

bsnr is a working tool in active use, not a finished standard. This file tracks planned features, known issues, and future work.

---

## Known issues

### Test output suppression via fprintf redirection
Currently `run_tests` uses `evalc('fn()')` to suppress test output in quiet
mode. This causes several problems: breakpoints are unreachable inside `evalc`,
figure handles created inside `evalc` are not visible to the caller, and
`evalc` can trigger implicit parallel pool initialisation in some MATLAB
versions (work around: `test_trimAnnotation` explicitly closes any open pool
at startup).

The proper fix: add a `verbose` parameter to each test function and redirect
`fprintf` calls to a no-op when `verbose=false`. This keeps output suppression
in the test functions rather than the runner, and eliminates all `evalc` usage
from `run_tests`.

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

### Contour and non-rectangular annotation support
Accept richer annotation formats from contour-based detectors (e.g. silbido
profundo — Conant et al. 2022, JASA 152(6)) and mask-based deep learning
outputs, in addition to the current rectangular box (t0, tEnd, freq[lo hi]).

Two natural extensions:
- **Contour input** — pre-computed instantaneous frequency track (time × Hz).
  `snrRidge` could accept a contour directly, skipping `tfridge` entirely.
  Strictly better SNR for any detector that outputs contours.
- **TF mask input** — binary mask of signal cells in a spectrogram.
  Signal power = mean PSD of masked cells; noise = unmasked cells.
  No frequency band or ridge tracking needed.

Rectangular box remains the fallback. Implementation deferred until real
contour/mask data and a target format (PAMGuard, Tethys, silbido) are
available for testing.

Note: Conant et al. (2022) implemented a pure MATLAB version of silbido
profundo — worth checking whether its contour output format could serve
as a reference implementation for the contour input interface.

**Why not LOESS smoothing of tfridge output?**
LOESS smoothing of the raw `tfridge` track (implemented, default off) helps
on synthetic audio with tight annotation bounds. On real data with loose
analyst-drawn boxes, the energy-trim heuristic selects noise-dominated edge
slices and the smooth fits the noise rather than the signal. The fundamental
problem is that simple energy heuristics cannot reliably distinguish call
energy from broadband noise — a learned contour tracker (silbido profundo)
is the right solution for general FM calls at low SNR.
Apply smoothing to the instantaneous frequency estimates from `snrRidge` and
`snrSynchrosqueeze` to reduce jitter. Candidate approaches: LOESS, GAM,
spline, or polynomial fits. Smoothed track would be stored in
`methodData.ridgeFreqSmooth` alongside the raw track.

### Real-world trimAnnotation validation — Casey 2019 D-calls
`examples/snr_dcalls_casey2019_trimmed.m` is a partial example applying
`trimAnnotation` to the D-call dataset before SNR estimation. Complete this
as a companion to `snr_dcalls_casey2019.m` showing the effect of trimming
on SNR distributions and paper correlation. Deferred pending prioritisation.
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
