# ArgyllUX UI Copy and Control Definitions

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** `control-ui-copy-deck.md`

---

## 1. Why This Doc Exists

ArgyllUX exposes real control over profiling, verification, troubleshooting, and analysis.

That is useful, but only if the product stays clear about:

- what each action does
- why a user would choose it
- what the default means
- what the risk is when a choice is wrong
- where ArgyllCMS terms belong and where they do not

---

## 2. Cross-Cutting Copy Rules

### 2.1 Keep front-door language plain

Use action labels that match user intent.

Preferred front-door labels:

- `New Profile`
- `Improve Profile`
- `Import Profile`
- `Import Measurements`
- `Match a Reference`
- `Verify Output`
- `Recalibrate`
- `Rebuild`
- `Spot Measure`
- `Compare Measurements`
- `Troubleshoot`
- `B&W Tuning`

Avoid raw Argyll tool names as primary labels.

### 2.2 Always explain the default

A tooltip or inline hint should explain why the default is usually the right starting point.

### 2.3 Always explain cost or risk

If a setting can waste paper, create misleading evidence, or push the user into the wrong workflow, say so.

### 2.4 Keep the import distinction explicit

This distinction must stay consistent across the product:

- `Import Profile` = finished ICC profile
- `Import Measurements` = raw measurement data used for analysis, comparison, rebuild, or improvement

### 2.5 Keep troubleshooting action-oriented

`Troubleshoot` copy should move the user toward evidence and next actions, not toward generic warnings.

### 2.6 Keep analysis language separate from troubleshooting language

- `Inspect` copy should describe evidence and views
- `Troubleshoot` copy should describe likely causes and next actions

### 2.7 Never imply that more complexity is automatically better

More patches, more aggressive correction, or more advanced settings are not automatically better than a stable print path and trustworthy measurements.

### 2.8 Keep clickable hit areas friendly

Every custom clickable surface must make its full visible control area clickable, including padding, row whitespace, and the space between an icon and label. Do not ship controls that only respond on text glyphs or icon pixels.

On macOS, custom compact controls should meet Apple control-size guidance as a floor, use explicit SwiftUI hit-testing shapes when styled manually, and provide hover or pressed feedback so the target feels responsive.

---

## 3. Product Truth Statements

These are reusable short truths.

### T-001 - Unmanaged target printing

**Profiling targets must be printed unmanaged.** If the application or printer driver changes the target colors, the profile will be built from the wrong data.

### T-002 - Media settings first

**Profiling cannot fix the wrong media setting.** Get the printer and paper settings stable first, then measure and profile.

### T-003 - Measurement quality first

**Check measurement quality before blaming the profile.** Bad reads, wrong strip detection, scaling errors, or unstable prints can ruin a profile.

### T-004 - Recalibrate before rebuild when drift is suspected

**If a setup used to be good and is now off, compare or recalibrate before rebuilding from scratch.**

### T-005 - B&W reality

**B&W tuning is about neutrality and tonal behavior. It is not a promise that every monochrome path becomes a normal ICC-profile workflow.**

---

## 4. Navigation Mapping

| Control area | Route |
|---|---|
| Home launcher | `Home` |
| Profile library and detail | `Printer Profiles` |
| Symptom diagnosis and Issue Cases | `Troubleshoot` |
| Measurement, gamut, and profile analysis | `Inspect` |
| Monochrome tuning | `B&W Tuning` |
| Printers, papers, Argyll path, storage, defaults | `Settings` |

Legacy route labels from earlier drafts should not appear in new UI copy.

---

## 5. Canonical Route and Section Labels

### Top-level routes

- `Home`
- `Printer Profiles`
- `Troubleshoot`
- `Inspect`
- `B&W Tuning`
- `Settings`

### Inspect subsection labels

- `Measurements`
- `Gamuts`
- `Profiles`

### Advanced area labels inside Printer Profiles

- `Device Links`
- `Calibrated Exports`
- `Model Profiles (MPP)`

Use `Model Profiles (MPP)` exactly in advanced contexts. Do not invent a generic replacement term.

---

## 6. Workflow Label Definitions

### `New Profile`

Use when the user is creating a new characterization workflow for a printer and paper path.

### `Improve Profile`

Use when the user is improving an existing profile with more or better targeted data.

### `Import Profile`

Use when the user is bringing in a finished ICC profile.

### `Import Measurements`

Use when the user is bringing in measurement data such as `.ti3` or similar CGATS-style evidence.

### `Match a Reference`

Use when the goal is to make one output behave more like another reference condition.

### `Verify Output`

Use when the goal is to decide whether current output is still trustworthy and what to do next.

### `Recalibrate`

Use when the goal is to restore a previously trusted calibrated state.

### `Rebuild`

Use when the goal is to create a new characterization result because recalibration or small improvements are not enough.

### `Troubleshoot`

Use for symptom-first entry into diagnosis and Issue Case creation.

### `B&W Tuning`

Use for monochrome-neutrality, tonal-smoothness, grayscale-wedge, and related monochrome maintenance work.

---

## 7. Required Profile Copy

Every profile list and detail view must include consistent verification language.

### Required labels

- `Last verification date`
- `Verified against file`
- `Print settings`
- `Result`

### Example result copy

- `Result: avg dE00 0.9, max 2.7`
- `Result: not verified yet`
- `Result: caution - long neutral tail`

### Imported profile with incomplete context

Use:

- `Printer & Paper Settings Unknown`

Avoid vague alternatives such as:

- `Unknown setup`
- `Unmapped`
- `Incomplete profile`

---

## 8. Import Copy Guidance

### 8.1 Import Profile

**Primary label:** `Import Profile`

**Short description:** Bring in a finished ICC profile.

**Inline guidance:** Use this when you already have a profile file and want to inspect it, compare it, verify it, or keep it in the library.

**Warning:** Importing a profile does not prove the original printer and paper settings.

### 8.2 Import Measurements

**Primary label:** `Import Measurements`

**Short description:** Bring in raw measurement data for analysis or follow-up work.

**Inline guidance:** Use this when you have `.ti3` or similar measurement data and want to compare it, inspect it, troubleshoot with it, improve a profile, or rebuild from it.

**Warning:** Measurements without context are weaker evidence. Keep the original file, assumptions, and provenance.

---

## 9. Troubleshoot and Issue Case Copy

### Troubleshoot entry prompts

Use plain-language symptom prompts such as:

- `Neutrals are off`
- `A color family is wrong`
- `Prints are too dark or light`
- `B&W has a cast`
- `This setup used to be good`
- `Verification failed`
- `This paper never looks right`
- `Measurement problem`

### Issue Case label

Use:

- `Issue Case`

Do not use legacy or generic alternatives that weaken the object identity.

### Issue Case section labels

- `Symptom`
- `Evidence`
- `Findings`
- `Next actions`
- `Resolution state`

---

## 10. Inspect Copy Guidance

### Measurements subsection

Prefer labels such as:

- `Measured vs Target`
- `Measured vs Baseline`
- `Neutral Drift`
- `Worst Patches`
- `Outliers`

### Gamuts subsection

Prefer labels such as:

- `Compare Profiles`
- `Image vs Output Gamut`
- `Overlap`
- `Likely clipping region`

### Profiles subsection

Prefer labels such as:

- `Internals`
- `Neutral Axis`
- `Black Generation`
- `Raw Dump`

Avoid exposing implementation labels like:

- `CGATS browser`
- `X3DOM viewer`
- `iccgamut front end`

---

## 11. Action and Control Copy

### 11.1 New Profile controls

#### `Patch Count`

- **Tooltip:** Controls how many color patches will be printed and measured.
- **Inline hint:** The default is usually the best balance of effort and accuracy.
- **Warning:** More patches do not compensate for a bad media setting or weak measurements.

#### `Improve Neutrals`

- **Tooltip:** Gives extra attention to grays and near-grays.
- **Inline hint:** Useful when smooth neutrals and neutral ramps matter.
- **Warning:** Use this when neutrals matter, not just because "more" sounds better.

#### `Use Existing Profile to Help Target Planning`

- **Tooltip:** Uses a prior profile to place new patches more intelligently.
- **Inline hint:** Helpful when you already have a decent profile and want to make the next one stronger.
- **Warning:** This helps target planning. It does not repair a broken print path.

### 11.2 Print and measurement controls

#### `Print Without Color Management`

- **Tooltip:** Ensures the target prints as raw target values.
- **Inline hint:** Targets used for profiling must print unmanaged.
- **Warning:** If the target prints with color management, the resulting profile will be wrong.

#### `Drying Time`

- **Tooltip:** Wait time before measurement.
- **Inline hint:** Fine-art and high-ink papers often need more time to stabilize.
- **Warning:** Measuring too soon can lock transient color into the profile.

#### `Measurement Mode`

- **Tooltip:** Reads the chart strip by strip or patch by patch.
- **Inline hint:** Strip mode is faster; patch mode is slower but more robust on difficult media.
- **Warning:** Switch modes when strip reading is unreliable instead of forcing bad data through.

### 11.3 Verify Output controls

#### `Compare to Earlier Measurements`

- **Tooltip:** Checks whether the setup has drifted since an earlier trusted run.
- **Inline hint:** Use this before rebuilding from scratch when the setup used to be good.
- **Warning:** Only compare against a baseline you trust.

#### `Show Worst Patches First`

- **Tooltip:** Surfaces the largest errors first.
- **Inline hint:** Use this to see whether the issue is isolated or broad.
- **Warning:** A few bad patches are clues, not automatic proof that the whole profile is bad.

### 11.4 Improve Profile controls

#### `Improvement Strategy`

- **Tooltip:** Chooses how the next pass should improve the profile.
- **Inline hint:** Start broad unless evidence already points to neutrals or one color range.
- **Warning:** Do not use targeted strategies to hide drift or media-setting mistakes.

#### `Target Problem Colors`

- **Tooltip:** Adds more measurements around a troublesome color family.
- **Inline hint:** Useful when one hue band is clearly weak.
- **Warning:** Only use this when evidence points to a real localized problem.

### 11.5 Recalibrate controls

#### `Recalibration Goal`

- **Tooltip:** Chooses whether to restore a previous stable state or simply verify it.
- **Inline hint:** Use recalibration when the setup used to be good and you want it back in line.
- **Warning:** Recalibration is not a cure for the wrong media setting or managed target printing.

### 11.6 B&W Tuning controls

#### `Gray Ramp Detail`

- **Tooltip:** Sets how finely the monochrome ramp is sampled.
- **Inline hint:** More steps reveal smoother detail, but take more time to measure.
- **Warning:** Higher detail is only useful when the print path is stable and measurable.

#### `Check Neutrality Through the Ramp`

- **Tooltip:** Emphasizes cast detection across highlights, midtones, and shadows.
- **Inline hint:** Use this when prints feel warm, cool, green, or magenta even if density looks acceptable.
- **Warning:** A cast may come from paper and viewing light as well as from the print path.

---

## 12. Settings Copy Guidance

### Required section labels

- `Printers`
- `Papers`
- `Argyll`
- `Storage`
- `Defaults`

### Argyll section actions

- `Choose Path`
- `Re-run Validation`

### Argyll status labels

- `Ready`
- `Partially Available`
- `Not Found`

---

## 13. Guidance Package Topics

These are not user-facing labels. They connect controls to deeper help.

- `G-PRINT-UNMANAGED`
- `G-MEDIA-SETTINGS-FIRST`
- `G-MEASUREMENT-QUALITY-FIRST`
- `G-RECALIBRATE-BEFORE-REBUILD`
- `G-IMPORT-PROFILE-VS-MEASUREMENTS`
- `G-ISSUE-CASE-WORKFLOW`
- `G-BW-TUNING-REALITY`

---

## 14. Implementation Notes

1. Treat this doc as the source of truth for first-pass labels and helper copy.
2. Do not collapse `Import Profile` and `Import Measurements` into one vague import surface.
3. Do not reintroduce old route labels in toolbars, empty states, or launcher text.
4. Do not prescribe grouped information with unnecessary visual-metaphor language in the product docs.

---

## 15. Cross-References

- [`00-product-overview.md`](00-product-overview.md) for product terminology
- [`01-information-architecture.md`](01-information-architecture.md) for route structure
- [`02-workflows-and-state-machines.md`](02-workflows-and-state-machines.md) for workflow definitions
- [`03-screen-specs.md`](03-screen-specs.md) for where these labels appear
- [`04-decision-engine.md`](04-decision-engine.md) for Troubleshoot and Issue Case guidance
- [`05-advanced-inspection.md`](05-advanced-inspection.md) for Inspect-route labels and views
