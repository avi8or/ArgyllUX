# ArgyllUX Decision Engine and Diagnostic System

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** `decision-engine-and-diagnostic-model.md`, `troubleshooting-and-measurement-diagnostics.md`, `rule-matrix-symptom-evidence-action.md`

---

## 1. Purpose

People usually do not arrive at a printer-profiling app wanting to "run verification." They arrive because something looks wrong.

ArgyllUX should let users start from the symptom, gather evidence, interpret what that evidence means, and then recommend the least-destructive next action.

This decision engine powers:

- `Troubleshoot`
- `Issue Case` findings
- action recommendations after `Verify Output`
- interpretation of imported `.ti3` / CGATS evidence

`Inspect` remains the place to study the data in depth. The decision engine is the place that turns evidence into action.

---

## 2. Evidence Hierarchy

When the engine makes a recommendation, it should rank evidence in this order:

1. Argyll-backed measurable facts
2. comparison against trusted prior data
3. workflow context and print settings
4. user-supplied environmental context
5. clearly labeled inference

### 2.1 Argyll-backed measurable facts

Examples:

- `colverify` comparison metrics
- `profcheck` fit behavior and worst patches
- `printcal` recalibration / verification outcomes
- `spotread` spot or repeatability readings

### 2.2 Trusted prior data

Good troubleshooting often depends on comparing the current state to a previous known-good run.

Examples:

- prior verification file
- baseline `.ti3`
- previous calibration
- prior trusted profile version

### 2.3 Workflow context

The engine should consider:

- printer and paper settings
- media preset
- whether the profile was imported or created in-app
- whether calibration exists
- whether the complaint is color, monochrome, or reference-matching related

### 2.4 User context

Some causes cannot be derived from color data alone:

- drying time
- viewing light
- paper batch change
- whether the issue changes under different light
- whether a dedicated monochrome mode was used

### 2.5 Inference

Inference is allowed only when the engine:

- labels it as inference
- shows the evidence it used
- offers a way to raise confidence

---

## 3. Scope

### In scope

- measurement-quality problems
- printer drift against a trusted baseline
- neutral drift
- hue-band weakness
- endpoint shifts
- profile weakness vs broader setup failure
- paper-white and black-point changes
- B&W cast or rough ramp
- deciding whether to `Verify Output`, `Recalibrate`, `Improve Profile`, `Rebuild`, `Match a Reference`, or stop blaming the profile

### Out of scope

The engine should not pretend it can directly diagnose these from color data:

- clogged nozzles
- head strikes
- bronzing
- gloss differential
- mechanical feed failures
- internal printer hardware faults

The app can record those concerns in notes or ask about them, but it should not invent certainty from measurement data.

---

## 4. Core Decision Principles

### 4.1 Validate before interpreting

Do not explain a neutral cast if the measurement data itself looks suspect.

### 4.2 Prefer the least destructive next action

Default recommendation order:

1. fix invalid assumptions or setup mistakes
2. remeasure suspect data
3. compare to a trusted baseline
4. recalibrate if drift is likely and supported
5. improve an existing profile
6. rebuild
7. create a fully new profile
8. move to reference-matching if the real goal is another output condition

### 4.3 Keep troubleshooting separate from analysis

- `Troubleshoot` should answer what to do next.
- `Inspect` should answer what the evidence looks like in detail.

### 4.4 Separate maintenance from characterization

If a setup used to work, compare and recalibrate before rebuilding from scratch.

### 4.5 Never hide uncertainty

Each recommendation should include:

- evidence used
- likely issue class
- confidence level
- best next action

---

## 5. Evidence Inputs

### 5.1 User symptom

Examples:

- neutrals are too warm
- one color range is off
- prints are too dark
- B&W has a cast
- this setup used to be good
- the verification result looks wrong

### 5.2 Workflow context

- current profile
- prior trusted profile
- printer and paper settings
- calibration history
- imported vs created profile state

### 5.3 Measurement artifacts

Primary evidence formats:

- `.ti3`
- comparable CGATS measurement files
- `.cal`
- profile files when needed for prediction or gamut context

### 5.4 Measurement assumptions

These materially change interpretation:

- instrument type
- strip vs patch mode
- M condition / filter state
- observer and illuminant
- spectral availability
- calibration state

### 5.5 Environmental notes

- drying time
- viewing light
- paper batch
- recent printer maintenance
- screen-vs-print context

---

## 6. Gate Model

The decision engine runs as a chain of gates.

### 6.1 Gate 0 - Can these files or objects be compared meaningfully?

Questions:

- Do they share patch identity or sample location?
- Are the values comparable?
- Is the metadata sufficient?

If not, stop and ask for mapping or clarification.

### 6.2 Gate 1 - Are the assumptions compatible?

Check:

- observer
- illuminant
- spectral / FWA handling
- measurement condition
- calibration state

If assumptions differ materially, call it out before interpreting the result.

### 6.3 Gate 2 - Is the evidence trustworthy enough to interpret?

Use Argyll-backed signals:

- missing patches
- partial read state
- worst-patch clustering
- long-tail behavior
- repeated-read instability
- strip-recognition problems

If the data looks weak, recommend remeasurement or setup audit before deeper diagnosis.

### 6.4 Gate 3 - Is the problem local, global, or comparative?

Problem classes:

- `local` - neutrals, one hue family, one tonal band, one region
- `global` - broad shift across the output
- `comparative` - used to be good, compare today vs prior, compare this vs reference

### 6.5 Gate 4 - Choose the least-destructive next action

Possible recommendations:

- remeasure suspect rows or patches
- compare against a baseline
- `Recalibrate`
- `Improve Profile`
- `Rebuild`
- `New Profile`
- `Match a Reference`
- `B&W Tuning`
- explain that the likely issue is viewing, paper, or gamut rather than profile math

---

## 7. Observable Signals

### 7.1 Data-quality signals

- completeness
- average / median / p90 / max delta E
- worst-patch geography
- outlier clustering by row or strip
- repeated-read stability

### 7.2 Color-behavior signals

- neutral-axis drift
- hue-band weakness
- highlight / midtone / shadow behavior
- paper-white and black-point shifts
- comparative shift against trusted baseline

### 7.3 Contextual signals

- paper or media setting may be a guess
- target may have been measured too early
- complaint changes under different light
- complaint is really screen-vs-print only
- dedicated monochrome mode was used

---

## 8. Symptom Routing

Each symptom module should produce:

- evidence summary
- likely cause class
- confidence
- best next action
- optional advanced alternatives

### 8.1 Warm / cool neutrals

**Evidence to prioritize:**

- neutral drift by tonal band
- paper white shift vs baseline
- whether the rest of the gamut is broadly healthy
- whether outliers are localized

**Likely paths:**

- viewing-light / paper-white issue
- neutral-axis profile weakness
- printer drift
- a few bad measurements

**Best next actions:**

- `Compare Measurements`
- `Improve Profile` with neutral targeting
- `Recalibrate`
- remeasure suspect rows

### 8.2 Specific color range is off

**Evidence to prioritize:**

- hue-band summary
- whether the problem is local or broad
- spot comparison against a saved reference
- likely gamut-limit context

**Best next actions:**

- `Improve Profile` with targeted color range
- `Troubleshoot` print-path or intent choice
- `Recalibrate` if it used to be fine
- explain likely gamut limits when the target color is physically out of reach

### 8.3 Prints too dark / too light

**Evidence to prioritize:**

- print-vs-screen or print-vs-reference distinction
- current verification state
- paper type and expected contrast
- viewing light and display-brightness context

**Best next actions:**

- explain screen / viewing mismatch when printer evidence is healthy
- review paper and media limitations
- `Verify Output`
- `Recalibrate` or `Rebuild` only when measurement evidence supports that

### 8.4 B&W cast or rough ramp

**Evidence to prioritize:**

- wedge or grayscale data
- neutrality by tonal band
- whether dedicated monochrome mode is in use
- visual notes from known-good test images

**Best next actions:**

- `B&W Tuning`
- media-setting review
- controlled-light evaluation

**Guardrail:** do not route this automatically into generic color-profile rebuilds.

### 8.5 Profile was good, now off

**Evidence to prioritize:**

- current vs trusted baseline
- whether paper, paper batch, or media settings changed
- existence of calibration history

**Best next actions:**

- `Compare Measurements`
- `Recalibrate` if the workflow supports it
- `Rebuild` only if recalibration or comparison says the shift is larger than maintenance

### 8.6 Verification failed

**Evidence to prioritize:**

- `profcheck` histogram
- sorted worst patches
- physical clustering of outliers
- whether assumptions match
- whether the target was printed unmanaged

**Best next actions:**

- remeasure suspect rows
- fix setup mistakes
- rerun comparison with matched assumptions
- `Improve Profile` or `Rebuild` only after data quality is no longer the main issue

### 8.7 Measurement / instrument problem

**Evidence to prioritize:**

- repeatability checks
- repeated row failures
- connection/communication errors
- instrument calibration status

**Best next actions:**

- `Spot Measure` repeatability checks
- switch strip vs patch reading mode if needed
- resume and re-read with the measurement workflow
- stop the user from rebuilding until the measurement process looks trustworthy

### 8.8 Paper never looks right

**Evidence to prioritize:**

- issue appears only on this paper
- media preset is uncertain
- multiple profiles on this paper still disappoint

**Best next actions:**

- review printer and paper settings first
- run `Troubleshoot`
- start `New Profile` only after the print path itself is believable

### 8.9 Reference mismatch

**Evidence to prioritize:**

- measured reference
- measured current output
- mismatch distribution

**Best next action:**

- `Match a Reference`

### 8.10 Vague or incomplete complaint

**Confidence:** always low until enough evidence exists.

**Best next actions:**

- `Import Measurements` if the user has data
- `Spot Measure` for quick evidence
- `Verify Output` if there is already a profile and current chart data

---

## 9. Imported Measurement Analysis

Imported `.ti3` and related data should be treated as evidence, not as a dead upload.

### 9.1 Accepted directions after import

- inspect the data
- compare it to a target or baseline
- verify a profile against it
- use it to improve a profile
- use it to rebuild
- attach it to an `Issue Case`

### 9.2 Derived views the engine should produce

- measured vs target summary
- measured vs baseline summary
- neutral view
- hue-band view
- tonal view
- white / black point view
- outlier map
- assumptions panel

### 9.3 Output contract

Every imported-measurement analysis should return:

- what was compared
- assumptions used
- key findings
- confidence
- recommended next action

---

## 10. Issue Classification Heuristics

Quick classification rules:

- **good average, bad tail** -> likely local misreads or print defects
- **neutrals bad, gamut mostly okay** -> likely `Improve Profile` with neutral targeting
- **one hue band weak** -> likely localized improvement
- **uniform global shift from baseline** -> likely drift or setup change
- **paper white changed more than the body of the gamut** -> likely paper / viewing issue
- **massive mismatch everywhere** -> likely wrong profile, wrong media setting, or managed target print

The engine should classify. It should not silently "fix" the evidence.

---

## 11. Follow-Up Actions the Engine Can Create

The engine may directly recommend or launch:

- `Compare Measurements`
- `Spot Measure`
- `Verify Output`
- `Recalibrate`
- `Improve Profile`
- `Rebuild`
- `New Profile`
- `Match a Reference`
- `B&W Tuning`
- `Import Measurements`

If troubleshooting is underway, those actions should attach back to the active `Issue Case`.

---

## 12. Confidence Model

### High confidence

Use when:

- one issue class is strongly supported by measurement evidence
- assumptions are compatible
- no major workflow ambiguity remains

### Medium confidence

Use when:

- two plausible causes remain
- one important context element is missing

### Low confidence

Use when:

- mapping is weak
- assumptions conflict
- objective evidence is thin

Low confidence should lead to the smallest next evidence request that would genuinely change the recommendation.

---

## 13. Report Structure

Every diagnostic report or Issue Case findings summary should include:

1. what was analyzed
2. what the engine sees
3. most likely explanation
4. confidence
5. best next action
6. advanced alternatives
7. what would raise confidence

---

## 14. Product Guardrails

- Do not recommend a full rebuild before checking data quality.
- Do not recommend recalibration where the workflow or printer type makes it misleading.
- Do not promise a normal monochrome ICC workflow where Argyll does not provide one.
- Do not silently prune or reinterpret data.
- Do not blame the profile when the evidence points to paper, media setting, viewing light, or display setup.
- Do not default to a new profile when comparison, recalibration, or targeted improvement is the tighter fit.

---

## 15. Cross-References

| Document | Relationship |
|---|---|
| `00-product-overview.md` | Product terminology and guardrails |
| `01-information-architecture.md` | `Troubleshoot`, `Inspect`, and `Issue Case` positioning |
| `02-workflows-and-state-machines.md` | Follow-up jobs and workflow definitions |
| `03-screen-specs.md` | Troubleshoot and Issue Case layouts |
| `05-advanced-inspection.md` | Inspect-route analysis surfaces used by the engine |
| `06-ui-copy-and-controls.md` | Copy guidance for findings, actions, and evidence labels |
