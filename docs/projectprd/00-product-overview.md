# ArgyllUX Product Overview

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** `full-app-design-blueprint.md`, `product-functionality-workflows-spec.md` (overview sections)

---

## 1. Product Definition

ArgyllUX is a printer-profiling and print-troubleshooting desktop application built around ArgyllCMS.

The product model is intentionally simple on the surface:

- `Printer Profiles` is the main library.
- `Troubleshoot` is the symptom-first route.
- `Inspect` is the analysis space.
- `B&W Tuning` is the dedicated monochrome workflow area.
- `Settings` owns support objects such as printers, papers, defaults, storage, and toolchain configuration.

Under the surface, every profile still belongs to a specific printer, paper, and print-settings context. That context matters technically, but it is not the front-door noun the product asks users to think in.

ArgyllUX exists because ArgyllCMS is organized around command-line tools (`targen`, `printtarg`, `chartread`, `colprof`, `profcheck`, `printcal`, `spotread`, `colverify`, `refine`), while users think in goals:

- make a new profile
- import a profile I already trust
- inspect a `.ti3`
- figure out why neutrals are off
- verify whether output still holds up
- match a reference more closely

The app serves two audiences:

- **Guided users** who want correct workflows and plain language
- **Expert users** who want the real assumptions, files, diagnostic views, and command trace without reconstructing Argyll by hand

---

## 2. Product Boundaries

### In scope

- Printer profiling based on printed targets and measured charts
- External ArgyllCMS-based verification, recalibration, rebuild, and comparison workflows
- Import and management of finished ICC profiles
- Import and interpretation of measurement data such as `.ti3` / CGATS
- Symptom-first troubleshooting with evidence, findings, and saved `Issue Cases`
- Profile inspection, gamut analysis, measurement analysis, and profile-internals views
- B&W tuning, neutrality checks, and grayscale-oriented maintenance
- Versioned library behavior around profiles, measurements, calibrations, device links, and related artifacts
- Persistent jobs with pause/resume behavior where the workflow is long-running or print-dependent

### Out of scope

- A top-level instrument-management product surface
- Direct USB-device implementation in this pass
- Pretending every print problem can be solved with a new ICC profile
- Display calibration as a primary workflow
- Scanner or camera profiling as primary product areas
- Acting as a complete front end for every Argyll utility regardless of printer relevance

Instrument status remains visible in the shell and in relevant workflows, but device management is not a top-level route.

---

## 3. Design Principles

### 3.1 Goal-first entry points

Users start from what they want to do, not from Argyll tool names.

The front-door task set is:

1. `New Profile`
2. `Improve Profile`
3. `Import Profile`
4. `Import Measurements`
5. `Match a Reference`
6. `Verify Output`
7. `Recalibrate`
8. `Rebuild`
9. `Spot Measure`
10. `Compare Measurements`
11. `Troubleshoot`
12. `B&W Tuning`

### 3.2 Profile-first library model

The main library is `Printer Profiles`, not loose files and not an abstract "configuration" browser. A profile is the thing users expect to browse, compare, import, verify, improve, and troubleshoot.

That does not remove the underlying print context. It means the print context supports the profile instead of competing with it for front-door language.

### 3.3 Context stays explicit

Every profile still records the printer, paper, media settings, quality mode, calibration state, and measurement assumptions that produced it.

When the app cannot recover that context from an imported profile, it must say so plainly:

- `Printer & Paper Settings Unknown`

### 3.4 Troubleshoot is symptom-first

Users rarely think "I should run verification." They think:

- my blacks are magenta
- this paper never looks right
- this setup used to be fine
- one color family is off

`Troubleshoot` exists for that real behavior. It creates a persistent `Issue Case`, gathers evidence, explains likely causes, and routes to the least-destructive next action.

### 3.5 Inspect is for analysis, not repair

`Inspect` is separate from `Troubleshoot`.

- `Troubleshoot` answers what is likely wrong and what to do next.
- `Inspect` answers what the data, gamut, or profile behavior looks like in detail.

### 3.6 Measurement data is evidence, not just an upload

Imported `.ti3` and related data are not just files to store. They are evidence the app should interpret into findings:

- measured vs target
- measured vs baseline
- neutral drift
- hue-band weakness
- endpoint shifts
- outlier clustering

### 3.7 Verification should lead to action

Verification is not a separate philosophy or a vanity metric. It exists to help users decide whether to trust output, recalibrate, rebuild, improve a profile, or stop blaming the profile for a paper or viewing problem.

### 3.8 Honest B&W modeling

`B&W Tuning` is plain language for grayscale-focused work such as linearization, neutrality checks, correction, and validation. The app must stay honest that these workflows often produce calibration curves, correction assets, and evaluation results rather than a conventional monochrome ICC profile built by `colprof`.

---

## 4. ArgyllCMS Constraints

The application should simplify ArgyllCMS without fictionalizing it.

### 4.1 Target generation scope

`targen` can generate grayscale, RGB, CMY, CMYK, and N-color target values. ArgyllUX can support measurement and planning for any of those target families where they help printer workflows.

### 4.2 Standard ICC profile creation scope

`colprof` creates RGB, CMY, or CMYK ICC profiles. The product must not imply that every possible ink configuration automatically maps to a normal ICC printer profile.

### 4.3 Measurement vs profile vs calibration

The app must distinguish between:

| Category | Outcome |
|---|---|
| Measured data | `.ti3` / CGATS evidence used for analysis, comparison, rebuild, or improvement |
| Standard profile build | ICC profile via `colprof` where the workflow supports it |
| Calibration / linearization | `.cal` and related maintenance state |
| Alternative model path | Device links, calibrated exports, and `Model Profiles (MPP)` where standard ICC is not the best fit |

### 4.4 `Improve Profile` is a product term

`Improve Profile` means improving an existing profile with better or more targeted data. It may involve:

- adding more patches
- targeting neutrals
- targeting a weak hue range
- adding image-derived or spot-derived colors
- rebuilding and comparing to the prior version

It does **not** mean the Argyll `refine` command. `refine` belongs to `Match a Reference`.

### 4.5 `Recalibrate` and `Rebuild` are different

- `Recalibrate` restores a previously trusted calibrated state when the workflow supports it.
- `Rebuild` creates a new characterization result because the old assumptions or data are no longer good enough.

The app must never collapse those into one vague maintenance action.

### 4.6 `B&W Tuning` produces tuning assets

The front-door label is friendly, but the technical model must explain that B&W workflows may produce:

- calibration curves
- correction assets
- validation runs
- driver-mode tuning guidance

not just "a black-and-white profile."

### 4.7 Instrument status is contextual

ArgyllUX should surface connected-instrument readiness, calibration warnings, and measurement compatibility, but it should not require a dedicated top-level device-management destination to do useful work.

---

## 5. User-Facing Terminology

| Technical / backend concept | User-facing term | What the user should understand |
|---|---|---|
| Print context | **Printer and paper settings** | The printer, paper, media setting, quality mode, and related assumptions behind a profile |
| Workflow session | **Job** | Saved work with progress, files, timers, and next actions |
| ICC library object | **Printer Profile** | A finished profile the user can browse, verify, inspect, improve, compare, or export |
| Imported ICC with missing provenance | **Printer & Paper Settings Unknown** | The profile file exists, but the app cannot prove its original print context |
| Measurement set | **Measurements** | Readings captured from charts, spot reads, or imported data |
| Verification result | **Verification** / **Verify Output result** | Evidence about whether the current output still matches expectations |
| Troubleshooting record | **Issue Case** | A saved investigation linking symptoms, evidence, findings, and follow-up jobs |
| MPP model profile | **Model Profiles (MPP)** | An advanced Argyll model-based profile type used when standard ICC is not the whole answer |

---

## 6. Domain Model

### 6.1 Core entities

#### Printer

| Attribute | Description |
|---|---|
| Make / model / nickname | Physical device identity |
| Transport style | Sheet-fed, roll, flatbed, etc. |
| Supported quality modes | Resolution and quality presets |
| Monochrome path notes | Whether the printer has dedicated B&W behavior worth tracking |
| Notes | User-entered notes |

#### Paper

| Attribute | Description |
|---|---|
| Vendor / product name | Commercial paper identity |
| Surface class | Matte, luster, glossy, baryta, canvas, etc. |
| Weight / thickness | Relevant physical properties |
| OBA / fluorescence notes | Whether optical brighteners matter |
| Notes | User-entered notes |

#### Instrument

| Attribute | Description |
|---|---|
| Make / model | Device identity |
| Capabilities | Spot, strip, spectral, filter/measurement modes |
| Patch-size limits | Minimum and recommended patch dimensions |
| Calibration requirements | White tile, warmup, other checks |
| Last-seen / readiness state | Recent shell-visible status |

#### Printer Profile Context

Internal object describing the print path a profile belongs to. This is not the primary browsing noun in the product.

| Attribute | Description |
|---|---|
| Printer | Linked printer |
| Paper | Linked paper |
| Media setting / preset | Driver or RIP media choice |
| Quality mode / resolution | Print-quality choice |
| Print path notes | Unmanaged-printing reminders, RIP notes, feed notes |
| Calibration assumptions | Whether calibration is expected and which baseline applies |
| Measurement assumptions | Instrument mode, observer, illuminant, spectral/FWA context |

#### Printer Profile

The main user-facing library object.

| Attribute | Description |
|---|---|
| Name | User-visible profile name |
| File | The `.icc` / `.icm` file |
| Context | Linked Printer Profile Context where known |
| Context status | Known context or `Printer & Paper Settings Unknown` |
| Source measurements | Measurement set used to build it, when known |
| Imported / created | Provenance of the profile |
| Active / archived / superseded | Trust-chain state |
| Last verification date | Most recent verification timestamp |
| Verified against file | Measurement or chart file used for the last verification |
| Relevant print settings | Snapshot of the settings that matter for trust |
| Delta E summary | Current verification headline metrics |
| History | Supersedes / superseded-by lineage |

#### Measurements

| Attribute | Description |
|---|---|
| File | `.ti3` / CGATS or equivalent |
| Measurement type | Chart read, spot set, comparison basis, imported evidence |
| Assumptions | Instrument mode, observer, illuminant, spectral/FWA context |
| Patch mapping basis | `SAMPLE_ID`, `SAMPLE_LOC`, or equivalent |
| Import provenance | Original source and timestamp |
| Derived findings | Neutral drift, hue weakness, endpoint shift, outlier notes |

#### Calibration Asset

| Attribute | Description |
|---|---|
| File | `.cal` or related asset |
| Baseline / recalibration history | Initial and later states |
| Applicability | Which contexts or workflows it supports |
| Verification history | Checks performed against the calibration target |

#### Advanced Profile Assets

These live in the advanced area of `Printer Profiles`.

| Asset | Description |
|---|---|
| `Device Links` | Direct source-to-destination transforms for specific workflow paths |
| `Calibrated Exports` | Compatibility outputs where calibration is carried with deployment |
| `Model Profiles (MPP)` | Model-based Argyll profile outputs kept in advanced language only |

#### Verification Result

| Attribute | Description |
|---|---|
| Basis | Profile vs measurements, profile vs verification chart, or measurements vs measurements |
| Summary metrics | Average, median, p90 / p95, max delta E |
| Findings | Neutral drift, weak hue sectors, endpoint changes, outliers |
| Recommendation | Accept, improve, recalibrate, rebuild, or troubleshoot |
| Linked source | File or profile used as the comparison basis |

#### Issue Case

| Attribute | Description |
|---|---|
| Reported symptom | What the user says is wrong |
| Linked profiles | Current profile, prior trusted profile, or imported profile |
| Linked measurements | Evidence files used in the case |
| Linked baselines | Prior trusted measurements, verification files, or calibrations |
| Findings | Structured evidence-backed interpretation |
| Recommended next actions | Ranked workflow suggestions |
| Follow-up jobs | Work spawned from the case |
| Resolution state | Open, resolved, superseded |

#### Job

| Attribute | Description |
|---|---|
| Workflow type | `New Profile`, `Improve Profile`, `Verify Output`, etc. |
| Linked profile / context | The profile or underlying context the job operates on |
| Status | Draft, ready, drying, measuring, review, completed, blocked, paused |
| Current phase | Exact workflow step |
| Resume data | Checkpoint state |
| Timers | Drying or wait-state timers |
| Notes / warnings | User notes and system notes |

### 6.2 Relationship summary

```text
Printer
  \\
   -> Printer Profile Context <- Paper
             |
             +-> Printer Profile
             |      +-> Verification Result
             |      +-> Device Links
             |      +-> Calibrated Exports
             |      +-> Model Profiles (MPP)
             |
             +-> Calibration Asset
             |
             +-> Job
                     +-> Measurements

Issue Case
  +-> links to Printer Profile
  +-> links to Measurements
  +-> links to Calibration Asset
  +-> spawns follow-up Jobs
```

Key integrity rules:

- Every created profile traces back to measurements and a profile context.
- Imported profiles may exist without complete context, but the missing context must stay visible.
- Every profile can carry verification history.
- Every troubleshooting path can become a saved `Issue Case`.
- Measurements are reusable evidence across verification, comparison, rebuild, and troubleshooting.

---

## 7. Cross-Cutting Requirements

### 7.1 Verification summary on every profile

Every profile list and detail view must show:

- `last verification date`
- `verified against file`
- relevant print settings
- delta E result summary

### 7.2 Separate imports by user intent

The app must clearly distinguish:

- `Import Profile` = finished ICC profile
- `Import Measurements` = raw measurement data used for analysis, comparison, rebuild, or improvement

### 7.3 Reuse valid evidence

The app should reuse existing good work wherever possible:

- rebuild from trusted `.ti3`
- compare against older measurements
- verify against a known verification file
- improve a profile without restarting blindly

### 7.4 Preserve print reality

Printing, drying, measuring, and remeasuring are real stages with saved state. The product must not flatten them into fake one-click flows.

### 7.5 Show lineage, not loose files

Users should always be able to tell:

- which measurements produced a profile
- which verification file last checked it
- whether the current state is trusted or only imported
- what changed between versions

---

## 8. Acceptance Criteria

A user should be able to say:

1. "I can browse my work as printer profiles instead of hunting through loose files."
2. "I can tell the difference between importing a finished profile and importing measurements."
3. "I can see when a profile was last verified and what file it was verified against."
4. "I can start from a symptom, save the investigation, and come back to it as an Issue Case."
5. "I can inspect measurements, gamuts, and profile behavior without mixing analysis into troubleshooting."
6. "I can recalibrate, rebuild, or improve a profile without those actions being blurred together."
7. "I can work with imported profiles even when the original printer and paper settings are unknown."

---

## 9. Copy Guidance

### Preferred front-door language

- `Printer Profiles`
- `Troubleshoot`
- `Inspect`
- `Measurements`
- `Gamuts`
- `Profiles`
- `New Profile`
- `Improve Profile`
- `Import Profile`
- `Import Measurements`
- `Match a Reference`
- `Verify Output`
- `Recalibrate`
- `Rebuild`
- `B&W Tuning`
- `Issue Case`

### Keep out of primary nav and launcher language

- print condition
- workflow session
- MPP profile
- instrument manager
- ICC tag browser
- CGATS browser

Those terms can appear in advanced explanations, metadata, or technical disclosure where they are genuinely useful.
