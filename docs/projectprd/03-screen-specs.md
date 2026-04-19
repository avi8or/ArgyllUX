# ArgyllUX Screen Specifications

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** `screen-wireframes-interaction-spec.md`, screen/navigation sections of `workflow-state-machine-screen-map.md`

---

## 1. Interface Intent

The UI should answer these questions quickly:

1. What am I trying to do?
2. Which profile am I working on?
3. What is the next correct action?
4. What evidence do I have?
5. Where do I go if something looks wrong?

Every primary screen should make at least the first three answers visible without forcing the user into a technical layer.

---

## 2. Shell

### Top-level navigation

```text
Home
Printer Profiles
Troubleshoot
Inspect
B&W Tuning
Settings
```

These are the only app-wide routes.

### Top-strip utilities

- Search / Jump
- Instrument status
- Active-job count
- Alert count
- Help / utilities

### Layout regions

- Top strip for navigation and utilities
- Main content area for the current route
- Optional right inspector for `Recommended`, `Advanced`, and `Technical`
- Bottom active-work dock

### Shell wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| ArgyllUX | Home | Printer Profiles | Troubleshoot | Inspect | B&W Tuning | Settings | Search __________        |
| Instrument: i1Pro3 Ready | Jobs 4 | Alerts 2 | Help                                                          |
+------------------------------------------------------------------------------------------------------------------+
| Main content area                                                                      | Recommended | Adv | Tech |
|                                                                                        | local inspector tabs    |
+------------------------------------------------------------------------------------------------------------------+
| Active work: [P900 Rag profile - Drying 00:42] [ET-8550 issue case - Needs review] [B&W wedge - Measuring]     |
+------------------------------------------------------------------------------------------------------------------+
```

### Shell rules

- Primary nav and right-inspector tabs must not look interchangeable.
- Instrument state is visible in the shell but does not require a top-level route.
- The bottom dock is for active or resumable work only.

---

## 3. Home

### Purpose

`Home` is the operational overview and main entry surface.

### Content zones

1. start a task
2. active work
3. profile health
4. toolchain and instrument status

### Required actions on Home

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

`Troubleshoot` must be visually prominent.

### Home wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Home                                                                                                             |
|------------------------------------------------------------------------------------------------------------------|
| Start a task                           | Active work                          | Profile health                   |
| New Profile                            | P900 Rag v3 - Drying 00:42          | P900 Rag v3                      |
| Improve Profile                        | next: measure target                 | last verification: 2026-04-08    |
| Import Profile                         |--------------------------------------| verified against: verify_v2.ti3  |
| Import Measurements                    | ET-8550 issue case - Needs review    | settings: USFA / 2880 / MK       |
| Match a Reference                      | next: compare to baseline            | avg dE00 0.9, max 2.7            |
| Verify Output                          |--------------------------------------|----------------------------------|
| Recalibrate                            | Canon Luster compare - Waiting       | Canon Luster imported            |
| Rebuild                                | next: choose baseline                | Printer & Paper Settings Unknown |
| Spot Measure                           |                                      | not verified yet                 |
| Compare Measurements                   | Toolchain / instrument               |                                  |
| Troubleshoot                           | Argyll Ready | i1Pro3 Ready         |                                  |
| B&W Tuning                             |                                      |                                  |
+------------------------------------------------------------------------------------------------------------------+
```

### Interaction notes

- Each launcher action opens directly into that workflow.
- Each active-work item shows one next action.
- Profile-health summaries open the related profile detail.

---

## 4. Printer Profiles

### Purpose

`Printer Profiles` is the main library and the primary browsing destination.

### 4.1 Profile list

Each row in the list should show:

- profile name
- printer and paper context or `Printer & Paper Settings Unknown`
- state (`active`, `archived`, `superseded`, `imported`)
- `last verification date`
- `verified against file`
- relevant print settings
- delta E result summary

### Profile list wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Printer Profiles                                   Search ____________________  Filter  New Profile  Import      |
|------------------------------------------------------------------------------------------------------------------|
| P900 Rag v3                           Active                                                                    |
| Printer: Epson P900    Paper: Canson Rag Photographique                                                        |
| Last verification date: 2026-04-08   Verified against file: verify_v2.ti3                                     |
| Settings: USFA / 2880 / MK            Result: avg dE00 0.9, max 2.7                                            |
|------------------------------------------------------------------------------------------------------------------|
| Canon Luster House Profile            Imported                                                                  |
| Printer & Paper Settings Unknown      Verified against file: none                                               |
| Result: not verified yet                                                                                         |
+------------------------------------------------------------------------------------------------------------------+
```

### 4.2 Profile detail

Profile detail is the trust view for a single profile.

#### Required sections

- profile header
- verification summary
- linked measurements
- lineage and prior versions
- recent jobs
- contextual actions
- advanced assets

#### Required contextual actions

- `Improve Profile`
- `Verify Output`
- `Recalibrate`
- `Rebuild`
- `Match a Reference`
- `Inspect Measurements`
- `Inspect Gamut`
- `Inspect Profile`

### Profile detail wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| P900 Rag v3                                                                                           Active     |
| Printer: Epson P900 | Paper: Canson Rag Photographique | Settings: USFA / 2880 / MK                             |
|------------------------------------------------------------------------------------------------------------------|
| Verification summary                               | Contextual actions                                          |
| Last verification date: 2026-04-08                | Improve Profile                                              |
| Verified against file: verify_v2.ti3              | Verify Output                                                |
| Result: avg dE00 0.9, max 2.7                     | Recalibrate                                                  |
| Interpretation: trusted                           | Rebuild                                                      |
|------------------------------------------------------------------------------------------------------------------|
| Measurements                                      | Inspect                                                      |
| build_v3.ti3                                      | Measurements | Gamuts | Profiles                             |
| verify_v2.ti3                                     |                                                              |
|------------------------------------------------------------------------------------------------------------------|
| History                                           | Advanced assets                                              |
| v1 -> v2 -> v3                                    | Device Links                                                 |
|                                                    | Calibrated Exports                                           |
|                                                    | Model Profiles (MPP)                                         |
+------------------------------------------------------------------------------------------------------------------+
```

### Advanced-area rule

`Device Links`, `Calibrated Exports`, and `Model Profiles (MPP)` appear inside this route as advanced sections, not as primary nav items.

---

## 5. Job Detail

### Purpose

Job detail is the main working screen for active workflows.

### Layout

- header with job identity and state
- single next action
- phase timeline
- current-step workspace
- right inspector with `Recommended`, `Advanced`, `Technical`
- CLI live panel at the bottom when relevant

### Job detail wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| New Profile - P900 Rag                                                               Drying 00:42                |
| Next action: Wait for the drying timer or mark the target ready to measure                                      |
|------------------------------------------------------------------------------------------------------------------|
| Timeline: Context + Target + Print + Drying * + Measure + Build + Review + Publish                              |
|------------------------------------------------------------------------------------------------------------------|
| Current step workspace                                                        | Recommended                      |
| Drying guidance                                                               | Printer: Epson P900              |
| - printed 2026-04-18 09:14                                                    | Paper: Canson Rag                |
| - suggested wait: 2h                                                          | Instrument: i1Pro3               |
| [Mark Ready to Measure] [Pause Job]                                           |                                   |
+------------------------------------------------------------------------------------------------------------------+
| CLI: colprof ...                                                                                                 |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 6. Troubleshoot

### Purpose

`Troubleshoot` is the symptom-first route. It creates or continues an `Issue Case`.

### Entry screen

The first screen should ask what looks wrong, not which tool the user wants.

### Troubleshoot entry wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Troubleshoot                                                                                                     |
|------------------------------------------------------------------------------------------------------------------|
| What looks wrong?                                                                                                |
| Neutrals are off | A color family is wrong | Prints are too dark or light | B&W has a cast                      |
| This setup used to be good | Verification failed | This paper never looks right | Measurement problem              |
|------------------------------------------------------------------------------------------------------------------|
| Evidence                                                                                                         |
| Import Measurements | Use existing measurements | Link current profile | Add notes                               |
|------------------------------------------------------------------------------------------------------------------|
| Save as Issue Case or continue                                                                                   |
+------------------------------------------------------------------------------------------------------------------+
```

### Issue Case detail

Each Issue Case detail should include:

- symptom summary
- evidence list
- findings
- recommended next actions
- linked jobs
- resolution state

### Issue Case detail wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Issue Case - Warm neutrals on ET-8550 matte                                                                      |
|------------------------------------------------------------------------------------------------------------------|
| Findings                                                                                                         |
| 1. Neutral-axis drift is concentrated in midtones                                                                 |
| 2. Paper white differs from the last trusted run                                                                  |
| 3. The rest of the gamut is broadly acceptable                                                                    |
|------------------------------------------------------------------------------------------------------------------|
| Evidence                                                                                                         |
| current_profile.icc | baseline_2026-02.ti3 | current_verify.ti3                                                  |
|------------------------------------------------------------------------------------------------------------------|
| Next actions                                                                                                     |
| Compare Measurements | Verify Output | Improve Profile | Recalibrate                                             |
|------------------------------------------------------------------------------------------------------------------|
| Resolution state: Open                                                                                            |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 7. Inspect

### Purpose

`Inspect` is the analysis route. It is organized into three subsections:

- `Measurements`
- `Gamuts`
- `Profiles`

### 7.1 Measurements subsection

This subsection should support:

- `Spot Measure`
- `Compare Measurements`
- `.ti3` / CGATS tables
- measured-vs-target
- measured-vs-baseline
- derived findings such as neutral drift and outlier clustering

### Measurements wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Inspect > Measurements                                                                                            |
|------------------------------------------------------------------------------------------------------------------|
| Sources: build_v3.ti3 | verify_v2.ti3                                                                            |
|------------------------------------------------------------------------------------------------------------------|
| Summary                                                                                                          |
| Avg dE00 1.4 | max 5.8 | neutral drift in midtones | worst patches clustered in strip 7                         |
|------------------------------------------------------------------------------------------------------------------|
| View                                   | Table                                                                    |
| measured-vs-target plot                | Patch ID | L* | a* | b* | dE00 | notes                                 |
| filters: neutrals / shadows / outliers | ...                                                                       |
+------------------------------------------------------------------------------------------------------------------+
```

### 7.2 Gamuts subsection

This subsection should support:

- single-profile gamut view
- profile-vs-profile comparison
- image-gamut-vs-output-gamut comparison

### Gamuts wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Inspect > Gamuts                                                                                                  |
|------------------------------------------------------------------------------------------------------------------|
| Compare: P900 Rag v3 vs Canon Luster House Profile                                                                |
|------------------------------------------------------------------------------------------------------------------|
| 3D view / projection                         | Summary                                                             |
| overlay of two gamut surfaces                | overlap, likely clipping regions, intent notes                      |
+------------------------------------------------------------------------------------------------------------------+
```

### 7.3 Profiles subsection

This subsection should support:

- profile internals
- neutral-axis view
- black-generation behavior
- header and tag inspection

### Profiles wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Inspect > Profiles                                                                                               |
|------------------------------------------------------------------------------------------------------------------|
| P900 Rag v3                                                                                                      |
|------------------------------------------------------------------------------------------------------------------|
| Tabs: Overview | Internals | Neutral Axis | Black Generation | Raw Dump                                         |
|------------------------------------------------------------------------------------------------------------------|
| Selected view content                                                                                             |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 8. B&W Tuning

### Purpose

`B&W Tuning` is the monochrome-specific route.

### Required sections

- current printer and paper path
- grayscale wedge or evaluation target status
- neutrality summary
- tonal smoothness summary
- linked validation history
- contextual actions

### B&W Tuning wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| B&W Tuning                                                                                                       |
|------------------------------------------------------------------------------------------------------------------|
| Printer: P700 | Paper: Fiber | Path: Driver monochrome                                                           |
|------------------------------------------------------------------------------------------------------------------|
| Status                                                                                                           |
| Last validation: 2026-04-12 | neutrality: slight cool cast in shadows | smoothness: acceptable                  |
|------------------------------------------------------------------------------------------------------------------|
| Actions                                                                                                          |
| Print wedge | Measure wedge | Validate output | Open related Issue Case                                           |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 9. Settings

### Purpose

`Settings` owns support objects and application defaults.

### Required sections

- `Printers`
- `Papers`
- `Argyll`
- `Storage`
- `Defaults`

### Settings rules

- `Printers` and `Papers` live here, not as top-level library nouns.
- Argyll path, validation state, and re-run validation controls live under `Argyll`.
- Instrument status may appear here as support information, but it is not a primary destination.

### Settings wireframe

```text
+------------------------------------------------------------------------------------------------------------------+
| Settings                                                                                                         |
|------------------------------------------------------------------------------------------------------------------|
| Sections: Printers | Papers | Argyll | Storage | Defaults                                                        |
|------------------------------------------------------------------------------------------------------------------|
| Argyll                                                                                                           |
| Detected path: /Applications/Argyll/bin                                                                          |
| Status: Ready                                                                                                    |
| Actions: Choose Path | Re-run Validation                                                                          |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 10. Layout and Copy Rules

- Use the agreed route labels and action names exactly.
- Do not prescribe grouped information with unnecessary visual-metaphor language in the docs.
- Prefer `lists`, `rows`, `tables`, `panes`, `sections`, and `detail views`.
- Every profile list or detail example must include:
  - `last verification date`
  - `verified against file`
  - relevant print settings
  - delta E summary

---

## 11. Cross-References

| Spec | Relation to this document |
|---|---|
| `00-product-overview.md` | Product boundaries and terminology |
| `01-information-architecture.md` | Route structure and object model |
| `02-workflows-and-state-machines.md` | State machines that drive job detail and task flows |
| `04-decision-engine.md` | Troubleshoot findings and next-action logic |
| `05-advanced-inspection.md` | Detailed Inspect-route behavior |
| `06-ui-copy-and-controls.md` | Canonical labels and copy rules |
