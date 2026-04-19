# ArgyllUX Information Architecture

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** Navigation sections of `print-configuration-workflow-map.md`, `full-app-design-blueprint.md`, `screen-wireframes-interaction-spec.md`

---

## 1. Application Shell

The application shell is built around four structural regions:

1. top strip
2. main work surface
3. optional right inspector
4. bottom active-work dock

The center work surface always has priority as the window narrows.

### Top strip

The top strip holds the only app-wide navigation plus global utilities.

| Slot | Purpose |
|---|---|
| Primary navigation | Stable top-level routes described in section 2 |
| Search / Jump | Global search across profiles, measurements, jobs, papers, printers, and Issue Cases |
| Instrument status | Connected device, readiness state, and calibration warnings |
| Active-job count | In-progress job badge |
| Alert count | Items needing attention |
| Help / utilities | Documentation, logs, support utilities |

### Main work surface

The main work surface is where route content lives. Screen-specific support content may appear as sections, panes, split views, lists, rows, tables, and detail views. It is not a second navigation system.

### Right inspector

The right inspector is optional and local to the current route or job. It holds `Recommended`, `Advanced`, and `Technical` disclosure for the active context.

### Bottom active-work dock

The bottom dock shows active or resumable work only.

| Content | Behavior |
|---|---|
| Active jobs | Each item shows the job name, related profile, state, and next action |
| Drying timers | Countdown timers for printed work waiting to stabilize |
| Blocked work | Jobs waiting on missing files, device conflicts, or user action |
| Resume points | Paused jobs with a one-click resume action |

Selecting a dock item opens the related job detail.

---

## 2. Top-Level Navigation

### Primary navigation

```text
Home
Printer Profiles
Troubleshoot
Inspect
B&W Tuning
Settings
```

These are the only top-level product routes.

### Route intent

| Route | Purpose |
|---|---|
| `Home` | Operational overview, task launcher, active work, and high-level health |
| `Printer Profiles` | Main profile library plus related advanced assets |
| `Troubleshoot` | Symptom-first diagnosis, evidence review, and Issue Case management |
| `Inspect` | Measurement, gamut, and profile analysis workspaces |
| `B&W Tuning` | Dedicated monochrome tuning, validation, and related jobs |
| `Settings` | Printers, papers, defaults, storage, Argyll/toolchain configuration |

### Explicit non-routes

The following are intentionally **not** top-level navigation entries:

- a dedicated device-management route
- `Check`
- `Maintain`
- `Jobs`

Jobs remain contextual. Instrument state remains visible in the shell and in measurement-related screens.

---

## 3. Home

`Home` has four jobs:

1. launch work
2. surface active work
3. summarize current profile health
4. keep shell-level readiness visible

### Home content zones

| Zone | Purpose |
|---|---|
| Start a task | Goal-first actions such as `New Profile`, `Troubleshoot`, and `Import Measurements` |
| Active work | In-progress jobs with one clear next action |
| Profile health | Recent verification state and trust summaries for key profiles |
| Instrument and toolchain status | Quick readiness summary without making device management a route |

### Home launcher actions

The launcher should prefer the user-facing action names agreed for the product:

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

`Troubleshoot` must be prominent because it reflects how people actually start when something looks wrong.

---

## 4. Shared Object Model in Navigation

### Primary browsing object: Printer Profile

The library centers on the `Printer Profile`.

Each profile detail view should answer:

- what profile this is
- which printer and paper settings it belongs to
- whether that context is known or unknown
- when it was last verified
- what it was verified against
- whether it is active, archived, or superseded

### Supporting internal object: Printer Profile Context

The printer/paper/settings context still exists and remains structurally important, but it is not the main noun in the nav.

Users can reach printers and papers directly from `Settings`, and they can see a profile's context from within the profile detail.

### Durable troubleshooting object: Issue Case

`Issue Case` is the saved troubleshooting record. It links symptoms, evidence, findings, and follow-up jobs.

### Measurements as shared evidence

Measurements are reusable across:

- `Printer Profiles`
- `Troubleshoot`
- `Inspect`
- `B&W Tuning`

They are not buried under one route.

---

## 5. Route-Level Capability Summary

### 5.1 Printer Profiles

`Printer Profiles` is the main library and the primary browsing destination.

It should support:

- profile list and search
- profile detail with verification summary
- version history and lineage
- import of finished ICC profiles
- direct access to linked measurements
- contextual actions such as `Improve Profile`, `Verify Output`, `Recalibrate`, `Rebuild`, and `Match a Reference`

#### Advanced area inside Printer Profiles

This route also holds an advanced area for:

- `Device Links`
- `Calibrated Exports`
- `Model Profiles (MPP)`

The app should explain `Model Profiles (MPP)` once in plain language and then keep it in the advanced area. It should not be promoted into the main launcher or top-level nav.

### 5.2 Troubleshoot

`Troubleshoot` is a symptom-first space.

It should support:

- starting from an issue description
- attaching evidence and notes
- importing measurements as evidence
- opening or saving an `Issue Case`
- seeing ranked likely causes and recommended next actions
- spawning follow-up jobs such as `Verify Output`, `Recalibrate`, `Improve Profile`, or `B&W Tuning`

### 5.3 Inspect

`Inspect` is the analysis space with three stable subsections:

- `Measurements`
- `Gamuts`
- `Profiles`

Specific tools live inside those subsections instead of competing as top-level route names.

| Inspect subsection | Contains |
|---|---|
| `Measurements` | Spot reads, compare measurements, `.ti3` / CGATS tables, measured-vs-target, measured-vs-baseline, derived findings |
| `Gamuts` | Gamut viewing, profile comparison, image-gamut comparison |
| `Profiles` | Profile internals, neutral-axis views, black-generation behavior, header/tag inspection |

### 5.4 B&W Tuning

`B&W Tuning` is a dedicated area for:

- grayscale wedge work
- neutrality and tonal smoothness checks
- monochrome comparison and validation
- correction and recalibration workflows that are specific to monochrome output

### 5.5 Settings

`Settings` owns support objects and application-level configuration.

Required sections:

- `Printers`
- `Papers`
- `Argyll`
- `Storage`
- `Defaults`

`Printers` and `Papers` live here, not as top-level routes and not as the primary library nouns.

---

## 6. Printer Profiles Route Structure

### List level

The profile list should support:

- search
- filtering by printer, paper, status, and verification state
- clear display of verification summary
- obvious distinction between created profiles and imported profiles

Every list row should include:

- profile name
- printer and paper context, or `Printer & Paper Settings Unknown`
- last verification date
- verified against file
- relevant print settings
- delta E summary

### Detail level

Each profile detail should include:

- header summary
- verification summary
- linked measurements
- history / lineage
- recent jobs
- contextual actions
- advanced assets when present

### Import behavior

`Import Profile` should create or attach a profile object.

If the app cannot determine the original print context, the profile detail must surface:

- `Printer & Paper Settings Unknown`

That state is legitimate and should not block inspection or verification.

---

## 7. Troubleshoot Route Structure

### Entry layer

The entry layer begins with the user symptom, not the tool.

Common entry prompts:

- neutrals are off
- a color family is wrong
- prints are too dark or too light
- this setup used to be good
- B&W has a cast
- this paper never looks right
- I have measurements and need help interpreting them

### Investigation layer

The investigation view should bring together:

- current profile or profiles
- imported or existing measurements
- baseline comparisons
- findings the app derived from the evidence
- recommended next actions

### Saved-object layer

Any troubleshooting path can be saved as an `Issue Case`.

`Issue Case` detail should show:

- symptom
- evidence
- findings
- open questions
- recommended next actions
- linked jobs
- resolution state

---

## 8. Inspect Route Structure

### Measurements subsection

This subsection is the home for:

- `Spot Measure`
- `Compare Measurements`
- `.ti3` / CGATS tables
- measured-vs-target views
- measured-vs-baseline views
- derived findings such as neutral drift and outlier clustering

### Gamuts subsection

This subsection is the home for:

- gamut viewing
- profile-vs-profile comparison
- image-gamut-vs-output-gamut comparison

### Profiles subsection

This subsection is the home for:

- profile internals
- neutral-axis views
- black-generation behavior
- ICC header and tag inspection

---

## 9. Jobs and Cross-Route Behavior

Jobs are not a top-level route, but they remain a first-class concept.

### Job access points

Jobs are reachable from:

- `Home`
- the bottom dock
- `Printer Profiles` detail
- `Troubleshoot` / `Issue Case` detail
- `B&W Tuning`

### Cross-route rules

- A troubleshooting path may spawn jobs in any route.
- A profile detail may launch `Verify Output`, `Improve Profile`, `Recalibrate`, `Rebuild`, or `Match a Reference`.
- `Inspect` should open directly against the currently selected profile, measurements, or Issue Case evidence.

---

## 10. Copy and Layout Rules for IA

### Terminology rules

Use:

- `Printer Profiles`
- `Troubleshoot`
- `Inspect`
- `Issue Case`
- `Import Profile`
- `Import Measurements`

Avoid legacy front-door labels from earlier drafts.

### Layout-language rules

Do not prescribe grouped information with unnecessary visual-metaphor language when the intent is only a list, row, table, pane, section, or detail view.

Prefer neutral terms such as:

- list
- row
- table
- pane
- section
- detail view
- summary area

---

## 11. Cross-References

| Document | Scope |
|---|---|
| `00-product-overview.md` | Product boundaries, terminology, and domain model |
| `02-workflows-and-state-machines.md` | Workflow definitions and job lifecycles |
| `03-screen-specs.md` | Shell, route, and detail-screen layouts |
| `04-decision-engine.md` | Troubleshooting logic and evidence routing |
| `05-advanced-inspection.md` | Detailed Inspect-route behavior |
| `06-ui-copy-and-controls.md` | Labels, control text, and copy rules |
