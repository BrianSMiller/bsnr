# bsnr — Development Journey

This document describes how bsnr came to be, how it evolved, and what the
experience of co-developing a research software tool with an AI assistant
actually looks like in practice. It is not a tutorial or a user guide — it
is closer to a lab notebook, written while the experience is recent enough
to be honest about.

---

## Origin

bsnr started as a reproduction problem. A published paper (Miller et al. 2022)
reported SNR values for Antarctic blue whale D-calls computed with a specific
formula (Lurton 2010) applied to spectrogramSlices power estimates. The goal
was to reproduce those values from the published supplemental data and
understand why they couldn't be reproduced exactly — a systematic parameter
search eventually showed that the best achievable correlation was r ≈ 0.47,
and the original code was not available to resolve the discrepancy.

That reproduction effort became the seed of a more general tool: if you're
going to compute SNR for one dataset, you might as well build something that
works across datasets and methods. bsnr is the result.

---

## What it grew into

The original goal — reproduce a specific SNR value — sits alongside a much
larger body of work:

- Seven SNR estimation methods with a consistent interface
- Annotation trimming to standardise analyst box sizes
- Calibration pipeline for absolute acoustic levels
- Tethys I/O for interoperability with PAMGuard workflows
- Parallel processing for large datasets (10k+ annotations)
- A test suite with synthetic audio fixtures
- Published-data examples for three datasets (Casey 2019 D-calls, Common
  Ground ABZ calls, Common Ground parallel processing guide)
- A documentation site built with MATLAB's `publish`

This is more than was planned. Whether that is good or bad depends on your
perspective.

---

## Co-development with an AI assistant

bsnr was developed in extended sessions with Claude (Anthropic), used as a
collaborative coding partner rather than a code generator. The distinction
matters: the goal was not to prompt an AI and accept its output, but to
maintain architectural ownership while offloading implementation detail and
pattern repetition.

### What worked well

**Consistent patterns across files.** When a design decision was made —
say, the parallel processing threshold logic — applying it consistently to
`snrEstimateImpl`, `trimAnnotation`, and the test suite was fast and reliable.
The AI maintained the pattern correctly across all files in a session.

**Boilerplate and repetition.** Writing the same `arguments` block for seven
method functions, updating `functionSignatures.json`, threading a new parameter
through a call chain — these are tedious but straightforward tasks where AI
assistance genuinely accelerated work.

**Catching edge cases.** The AI often flagged cases that hadn't been considered:
what happens when the annotation is shorter than `nfft`? What if the noise
window falls outside the file? What if `parfor` is called with `showPlot=true`?
Some of these were anticipated; others weren't.

**Drafting documentation.** The getting started guide, this document, and the
architecture reference were drafted collaboratively and required relatively
little correction once the right framing was established.

### What didn't work well

**Symptom patching over root cause analysis.** The parallel pool problem
— where `test_trimAnnotation` kept starting a parpool unexpectedly — took
far longer to resolve than it should have. The AI kept patching symptoms
(adding `gcp` checks, toggling flags, removing and restoring `parpool` calls)
rather than stepping back to diagnose why the behaviour differed between
standalone and `run_tests` execution. The correct diagnosis (MATLAB's `evalc`
can trigger implicit parallel initialisation) only emerged after repeated
pushback. The fix was simple once the root cause was identified.

**API scope creep.** The ridge smoothing feature started as a straightforward
addition to `snrRidge` and ended up triggering an attempt to expose
`methodData` through `snrEstimate`'s public API — a significant change that
broke 9/13 tests and had to be reverted. The AI proposed the API extension
without adequately considering the scope and breakage risk. Reverting and
using inline code in the gallery was the right call, but cost significant time.

**String escaping in generated gallery code.** Python's `r"""..."""` raw strings
consistently produced unterminated MATLAB string literals when written to
`.m` files, because `\n` was not escaped as `\\n`. This happened multiple
times across multiple sessions. The fix (use `str_replace` directly rather
than Python string manipulation for MATLAB code) was obvious in retrospect.

**Context window loss.** Over long sessions, earlier architectural decisions
would exit the context window. The AI would occasionally propose solutions
that contradicted established patterns — reintroducing a `processOne` function
that had been deliberately removed, or suggesting a helper function that
duplicated existing logic. The session summary and architecture document
(this file's companion) are intended to mitigate this.

### The right mental model

The most productive framing was: the AI is a very capable junior collaborator
who knows the language well and can implement things quickly, but needs
explicit architectural guidance and will occasionally need to be corrected
firmly when going in the wrong direction. The human's job is to maintain
direction, question proposals that seem overcomplicated, and push back when
symptoms are being patched rather than root causes fixed.

The least productive framing was treating the AI as an oracle that would
produce correct solutions if given a sufficiently detailed prompt. Detailed
prompts helped, but judgment about whether a proposed solution was actually
correct remained entirely the human's responsibility.

---

## Tension: reproduction vs exploration

bsnr carries a tension that has not been fully resolved. On one side: it is
a reproduction tool, and the published-data examples need to keep working and
producing the same results. On the other: it is a vehicle for exploring SNR
estimation methods, and exploration requires trying things that might not work.

The ridge smoothing feature is the clearest example. It was a reasonable idea,
implemented correctly for the synthetic case, but failed on real data with
loose annotation bounds. The right response — document the limitation, keep
the feature as opt-in with a clear warning, and note silbido profundo as the
proper long-term solution — is defensible but not fully satisfying. The feature
adds complexity without being reliable enough to recommend.

The current approach to managing this tension:

- `experimental/` for things not ready to share
- `examples/` for things that work on real data
- Semantic versioning to signal breaking changes
- `todo.md` as an honest accounting of what works, what doesn't, and why

A more formal tier structure (core / methods / experimental) was considered
and deferred. The overhead of maintaining tier boundaries in a one-person
research tool felt disproportionate to the benefit.

---

## What worked as a workflow

**Session summaries in the context window.** Starting each session with a
compacted summary of previous work (stored in `/mnt/transcripts/`) meant
architectural context was available without re-reading code. The summaries
are not perfect — they miss nuance and occasionally get details wrong — but
they are much better than nothing.

**Uploading files rather than pasting code.** Giving the AI the actual current
version of a file, rather than trusting it to remember a version from earlier
in the session, consistently produced better results.

**Committing frequently.** Small commits with clear messages made it easy to
identify what changed when something broke, and made reverting straightforward.
The temptation to accumulate changes across features before committing was
usually a mistake.

**Saying "no" early.** When a proposed solution seemed overcomplicated,
saying so immediately and asking for a simpler approach was almost always
correct. The AI generally had a simpler solution available — it just hadn't
led with it.

---

## Current state

bsnr is a working tool in regular use. The test suite passes, the
documentation site is live, and the published-data examples reproduce their
target results (within the documented discrepancy for D-calls). The codebase
is larger than originally intended and carries some technical debt
(documented in `todo.md`), but is navigable.

The most important outstanding items:

1. **Test output suppression** — `evalc` in `run_tests` prevents breakpoint
   debugging. The fix (per-function `verbose` parameter) is known but not
   yet implemented.

2. **Contour annotation support** — the rectangular box format is a limitation
   for FM calls. Silbido profundo (Conant et al. 2022) is the right reference
   implementation to target.

3. **Mixture model analysis** — the TP/FP discrimination analysis
   (`experimental/snr_tp_fp_analysis_casey2019.m`) is a genuine research
   question that may become a note or publication.

---

## A note on sharing

bsnr is personal research software that has been shared, not a public standard.
That distinction shapes every decision about how much abstraction is worth
building, how much documentation is enough, and how much technical debt is
acceptable. The goal has never been to be everything to everyone — it has been
to be a reliable, understandable tool for a specific set of problems, with
enough documentation that the decisions made along the way can be understood
and questioned.

If this document is useful to anyone beyond its author, that is a bonus.
