# Getting Started with bsnr

## What bsnr does

bsnr estimates the signal-to-noise ratio (SNR) of bioacoustic detections in
hydrophone recordings. You provide an annotation — a time, frequency, and file
location — and bsnr measures signal power against a noise window drawn from the
same recording. Seven methods are available, from a simple spectrogram average
to ridge-tracking for FM calls. When instrument calibration is provided, bsnr
returns absolute levels in dB re 1 µPa.

---

## Installation

Clone or download the repository, then add it to your MATLAB path:

```matlab
addpath('C:\analysis\bsnr', '-begin')
```

**Dependencies** — bsnr requires the following packages:

GitHub repositories (free, open source):

| Package | Purpose |
|---|---|
| [soundFolder](https://github.com/BrianSMiller/soundFolder) | WAV file indexing and audio loading (`wavFolderInfo`, `getAudioFromFiles`) |
| [annotatedLibrary](https://github.com/BrianSMiller/annotatedLibrary) | Annotation utilities |

MATLAB toolboxes (licensed separately):

| Toolbox | Purpose |
|---|---|
| Signal Processing Toolbox | `spectrogram`, `designfilt`, `fsst`, `tfridge` |
| Parallel Computing Toolbox | Batch parallel processing (optional) |

Add all dependencies to your MATLAB path before running bsnr.

---

## Your first SNR estimate

bsnr includes a bundled Antarctic blue whale Z-call clip. This is the fastest
way to confirm everything is working:

```matlab
% Locate the bundled audio clip
audioDir = fullfile(fileparts(which('bsnr')), 'examples', 'audio', 'abw_z');
sf = wavFolderInfo(audioDir, '', false, false);

% Build an annotation struct
annot.soundFolder    = audioDir;
annot.t0             = sf(1).startDate + 17/86400;  % 17 s into clip
annot.tEnd           = annot.t0 + 21/86400;          % 21 s duration
annot.duration       = 21;
annot.freq           = [17 28];   % Hz
annot.channel        = 1;

% Estimate SNR
result = snrEstimate(annot, 'snrType', 'spectrogramSlices', 'showClips', true);
fprintf('SNR = %.1f dB\n', result.snr(1));
```

`snrEstimate` always returns a result table — even for a single annotation.
`result.snr(1)` extracts the scalar value.

---

## Your own data

Build an annotation struct with these required fields:

```matlab
annot.soundFolder = 'C:\data\deployment_01';  % folder containing WAV files
annot.t0          = datenum('2024-03-15 14:23:07', 'yyyy-mm-dd HH:MM:SS');
annot.tEnd        = annot.t0 + 8/86400;        % 8 s duration
annot.duration    = 8;                          % seconds
annot.freq        = [25 90];                    % Hz [low high]
annot.channel     = 1;
```

`t0` and `tEnd` are MATLAB datenums (days since year 0) or `datetime` objects.
`soundFolder` must contain WAV files whose filenames encode a timestamp —
`wavFolderInfo` detects the format automatically from the filename.

**Common mistake:** forgetting to set `annot.duration`. bsnr uses the duration
to derive the spectrogram window size (`nfft`). Without it, results may be
inconsistent across annotations.

### Tethys annotations

If your annotations are stored in a Tethys database or exported as Tethys
Detections XML, use `readTethysDetections` to convert them to bsnr format:

```matlab
% From a Tethys XML file
annots = readTethysDetections('detections.xml', 'C:\data\deployment_01');

% From a struct returned by a Tethys MATLAB client query
annots = readTethysDetections(tethysResult, soundFolderPath);

% When MinFreq_Hz / MaxFreq_Hz are absent in the Tethys document
annots = readTethysDetections('detections.xml', soundFolderPath, ...
    'freqFallback', [10 30]);

% Then estimate SNR as normal
result = snrEstimate(annots, 'snrType', 'spectrogramSlices', 'nfft', 512);
```

To write results back as Tethys-compatible XML (e.g. for NOAA NCEI archiving):

```matlab
writeTethysXml(result, annots, ...
    'project',      'SORP', ...
    'deploymentId', 'Casey2019', ...
    'software',     'bsnr', ...
    'outputFile',   'snr_results.xml');
```

`SNR_dB` and `ReceivedLevel_dB` (when calibration is provided) are written
as native Tethys `Detection.Parameters` fields — no user-defined extensions
needed.

---

## Choosing a method

| Method | Best for |
|---|---|
| `'spectrogram'` | General purpose; mean PSD across the annotation band |
| `'spectrogramSlices'` | Transient or pulsed calls; robust to short noise bursts |
| `'timeDomain'` | Broadband calls; fastest computation |
| `'ridge'` | FM tonal calls (upcalls, whistles); tracks instantaneous frequency |
| `'synchrosqueeze'` | FM calls at low SNR; sharper than ridge |
| `'quantiles'` | No noise window needed; within-window contrast |
| `'nist'` | Frame energy histogram; comparable to Raven Pro SNR NIST Quick |

When in doubt, start with `'spectrogramSlices'` — it is the method used in
Miller et al. (2021, 2022) and is the most widely validated.

---

## Batch processing

Pass a struct array or table of annotations. bsnr returns a result table with
one row per annotation:

```matlab
result = snrEstimate(annotations, 'snrType', 'spectrogramSlices', ...
    'nfft', 512, 'verbose', false);
disp(result)
% result.snr             — SNR in dB
% result.signalRMSdB     — signal level in dBFS (or dB re 1 µPa if calibrated)
% result.noiseRMSdB      — noise level
```

**Important:** always set `nfft` explicitly for batch processing. When `nfft`
is not set, bsnr derives it from the median annotation duration and issues a
warning — this can produce non-comparable SNR values across annotations of
different lengths. The sixth output `resolvedParams` records the exact
parameters used:

```matlab
[result, ~, ~, ~, ~, resolvedParams] = snrEstimate(annotations, 'nfft', 512);
resolvedParams.nfft     % confirms 512 was used
```

---

## Calibrated levels

To obtain absolute levels in dB re 1 µPa, provide instrument calibration:

```matlab
cal = metaDataCasey2019();   % use as a template for your own instrument
result = snrEstimate(annot, 'calibration', cal);
result.signalBandLevel_dBuPa   % calibrated signal level
result.noiseBandLevel_dBuPa    % calibrated noise level
```

See `examples/metaDataCasey2019.m` for the calibration struct format.

---

## Trimming annotation boxes

Analysts often draw annotation boxes with generous time and frequency margins.
`trimAnnotation` tightens the bounds to the central signal energy before
passing to `snrEstimate`:

```matlab
annotTrimmed = trimAnnotation(annot, 'showPlot', true);
result = snrEstimate(annotTrimmed, 'snrType', 'spectrogramSlices');
```

The diagnostic plot shows original (blue) and trimmed (red) bounds alongside
the cumulative energy profiles used to determine the trim.

---

## Troubleshooting

**`wavFolderInfo` returns empty** — the WAV filenames in `soundFolder` do not
contain a recognisable timestamp. bsnr requires filenames like
`2024-03-15_14-23-07.wav` or `20240315T142307.wav`. Rename files or use
`wavFolderInfo` directly to check what format is detected.

**All SNR values are NaN** — the noise window falls outside the file. Reduce
`noiseDelay` or switch `noiseLocation` to `'before'`. Check that `t0` and
`tEnd` are in the correct datenum units (days, not seconds).

**SNR values vary across runs with the same data** — `nfft` is being derived
from annotation duration rather than set explicitly. Set `nfft` to a fixed
value for reproducible batch results.

**Calibrated levels seem wrong** — verify that `hydroSensitivity_dB`,
`adPeakVolt`, and `frontEndGain_dB` in your calibration struct match your
instrument's data sheet. The `metaDataCasey2019` example provides a worked
reference.

---

## Next steps

- **[Method gallery](bsnr_gallery.html)** — all seven methods illustrated on
  synthetic and real recordings, with spectrogram, time series, and histogram
  displays
- **[Published-data examples](snr_dcalls_casey2019.html)** — reproduce SNR
  values from Miller et al. (2021, 2022) and Castro et al. (2024)
- **`help snrEstimate`** — full parameter reference with all defaults
- **`help trimAnnotation`** — annotation trimming parameter reference
