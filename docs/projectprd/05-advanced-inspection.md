# ArgyllUX Inspect Module

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** `gamut-inspection-and-ti-profile-inspector.md`  
**Navigation home:** `Inspect`

---

## 1. Where This Module Lives

`Inspect` is a top-level route dedicated to analysis. It is not the symptom-first route and it is not a debugging afterthought.

The route is organized into three stable subsections:

- `Measurements`
- `Gamuts`
- `Profiles`

The module is also reachable from contextual actions in:

- `Printer Profiles`
- `Verify Output`
- `Troubleshoot`
- `Issue Case` detail
- `Compare Measurements`
- `Match a Reference`

---

## 2. Product Position

`Inspect` exists to answer questions like:

- what does this `.ti3` actually say?
- where are the worst patches?
- is this problem local or broad?
- what changed relative to the last good run?
- is this likely a gamut issue?
- what is inside this profile?

`Troubleshoot` should tell the user what to do next.

`Inspect` should let the user study the evidence in detail.

---

## 3. Core Principle: Linked Views

Visual, tabular, and diagnostic views must stay linked.

Examples:

- click an outlier in a plot -> highlight the matching row in the table
- select a range in the table -> filter the visual view
- switch from measured-vs-target to measured-vs-baseline -> keep the selected patch or region in focus

Without linked views, the route becomes pretty but much less useful.

---

## 4. Inspect Subsections

### 4.1 Measurements

This subsection is the home for:

- `Spot Measure`
- `Compare Measurements`
- `.ti3` / CGATS table inspection
- measured-vs-target analysis
- measured-vs-baseline analysis
- derived findings such as neutral drift, hue-band weakness, endpoint shifts, and outlier clustering

#### Primary questions

- which patches are worst?
- is the problem in neutrals, one hue range, or the endpoints?
- does the current run differ from the baseline?
- do the measurements look trustworthy?

#### Required capabilities

- sortable table
- patch search by ID or sample location
- filters for neutrals, highlights, shadows, high-chroma points, outliers
- side-by-side and diff modes
- derived finding summaries
- metadata and assumptions panel

#### Argyll grounding

- `.ti3` / CGATS structure
- `colverify`
- `profcheck`
- `spotread`

### 4.2 Gamuts

This subsection is the home for:

- single-profile gamut viewing
- profile-vs-profile comparison
- image-gamut-vs-output-gamut comparison

#### Primary questions

- how do two profile gamuts differ?
- does this image really need the bigger gamut?
- is the issue likely clipping or something else?

#### Required capabilities

- 3D view
- projection or slice view
- compare overlay
- overlap / clipping summary
- intent and table-source controls where relevant

#### Argyll grounding

- `iccgamut`
- `viewgam`
- `tiffgamut`

### 4.3 Profiles

This subsection is the home for:

- profile internals
- neutral-axis views
- black-generation behavior
- header and tag inspection

#### Primary questions

- what is actually inside this profile?
- how does the neutral path behave?
- what does black generation look like?
- does this profile contain the metadata and tags I expect?

#### Required capabilities

- overview view
- internals view
- neutral-axis view
- black-generation view
- raw dump view

#### Argyll grounding

- `xicclu`
- `iccdump`

---

## 5. Measurement Workspace

### Purpose

Turn imported or linked measurement data into something a user can read and act on.

### Required views

- summary
- table
- measured-vs-target
- measured-vs-baseline
- neutral view
- hue-band view
- tonal view
- outlier map

### Required derived findings

The workspace should not stop at raw rows. It should surface:

- neutral drift
- weak hue sectors
- paper-white change
- black-point change
- outlier clustering
- likely measurement-quality concerns

### Measurement workspace layout

```text
+------------------------------------------------------------------------------------------------------------------+
| Inspect > Measurements                                                                                            |
|------------------------------------------------------------------------------------------------------------------|
| Source A: build_v3.ti3   Source B: verify_v2.ti3                                                                 |
|------------------------------------------------------------------------------------------------------------------|
| Summary                                                                                                          |
| avg dE00 1.4 | max 5.8 | neutral drift in midtones | outliers clustered in strip 7                              |
|------------------------------------------------------------------------------------------------------------------|
| View / plot area                               | Table                                                            |
| filters: neutrals / shadows / outliers         | Patch | L* | a* | b* | dE00 | notes                           |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 6. Gamut Workspace

### Purpose

Help users compare profile gamut behavior without pretending that bigger always means better.

### Required outputs

- 3D comparison
- overlap summary
- likely clipping regions
- note when the chosen table or intent changes what is being shown

### Reality guardrails

- a bigger gamut surface does not automatically mean a better print workflow
- backwards-table views may reflect mapping behavior, not only native device reach
- gamut views should support decision-making, not replace visual print evaluation

### Gamut workspace layout

```text
+------------------------------------------------------------------------------------------------------------------+
| Inspect > Gamuts                                                                                                 |
|------------------------------------------------------------------------------------------------------------------|
| Compare: P900 Rag v3 vs Canon Luster House Profile                                                               |
|------------------------------------------------------------------------------------------------------------------|
| 3D or projection view                          | Summary                                                          |
| overlay of selected gamuts                     | overlap, clipping regions, likely implication                    |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 7. Profile Workspace

### Purpose

Give users direct profile-behavior and metadata inspection without forcing them into external tools.

### Required views

- `Overview`
- `Internals`
- `Neutral Axis`
- `Black Generation`
- `Raw Dump`

### Profile workspace layout

```text
+------------------------------------------------------------------------------------------------------------------+
| Inspect > Profiles                                                                                                |
|------------------------------------------------------------------------------------------------------------------|
| P900 Rag v3                                                                                                      |
|------------------------------------------------------------------------------------------------------------------|
| Tabs: Overview | Internals | Neutral Axis | Black Generation | Raw Dump                                         |
|------------------------------------------------------------------------------------------------------------------|
| Selected view content                                                                                             |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 8. Tools and Actions Inside Inspect

These remain actions inside the subsections rather than top-level route names:

| Action | Lives in |
|---|---|
| `Spot Measure` | `Inspect > Measurements` |
| `Compare Measurements` | `Inspect > Measurements` |
| `Inspect Gamut` | `Inspect > Gamuts` |
| `Compare Profiles` | `Inspect > Gamuts` or `Inspect > Profiles` depending on focus |
| `Profile Internals` | `Inspect > Profiles` |
| `Compare Image Gamut to Output Gamut` | `Inspect > Gamuts` |

---

## 9. Required Table Behavior

Where data exists, the table layer should support:

- patch ID
- sample location
- device values
- XYZ
- Lab
- delta E vs target / profile / reference
- spectral values
- metadata and instrument info

Required actions:

- sort
- filter
- multi-select
- bookmark suspicious rows
- jump to worst rows
- jump to paper white / black point
- export filtered rows

---

## 10. Integration with the Rest of the Product

`Inspect` must integrate cleanly with:

- `Printer Profiles` -> open linked measurements, gamut, or profile internals
- `Verify Output` -> open evidence behind the summary
- `Troubleshoot` -> open the exact region or evidence the Issue Case discusses
- `Compare Measurements` -> continue analysis in `Measurements`
- `Match a Reference` -> inspect mismatch geometry and comparison results

The route should open with context when launched from elsewhere. Users should not have to rebuild the same selection state by hand.

---

## 11. Acceptance Criteria

A serious user should be able to say:

1. "I can inspect measurements as evidence, not just as opaque files."
2. "I can compare current readings to a target or to a prior trusted baseline."
3. "I can examine gamuts without confusing that analysis with troubleshooting."
4. "I can inspect profile internals, neutral behavior, and black generation inside the app."
5. "I can move from a profile, verification result, or Issue Case directly into the right inspect view."

---

## 12. Argyll Mapping Table

| Argyll tool or format | What it supports | Where it belongs in ArgyllUX |
|---|---|---|
| `iccgamut` | Profile gamut generation and viewing | `Inspect > Gamuts` |
| `viewgam` | Gamut overlays and intersections | `Inspect > Gamuts` |
| `tiffgamut` | Image-content gamut generation | `Inspect > Gamuts` |
| `profcheck` | Profile-fit inspection against measurements | `Inspect > Measurements` |
| `colverify` | Measurement-to-measurement comparison | `Inspect > Measurements` |
| `xicclu` | Neutral-axis and device-behavior inspection | `Inspect > Profiles` |
| `iccdump` | ICC header and tag dump | `Inspect > Profiles` |
| `.ti3` / CGATS | Human-readable measurement structure | `Inspect > Measurements` |

---

## 13. Cross-References

| Doc | Relationship |
|---|---|
| `00-product-overview.md` | Product model and terminology |
| `01-information-architecture.md` | Route structure for `Inspect` |
| `02-workflows-and-state-machines.md` | Workflows that open analysis views |
| `03-screen-specs.md` | Screen layouts for the Inspect route |
| `04-decision-engine.md` | How Troubleshoot uses Inspect views as evidence surfaces |
| `06-ui-copy-and-controls.md` | Labels and control copy used inside Inspect |
