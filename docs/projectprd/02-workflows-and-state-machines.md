# ArgyllUX Workflows and State Machines

**Status:** Consolidated spec  
**Date:** 2026-04-18  
**Supersedes:** Workflow sections of `print-configuration-workflow-map.md`, `product-functionality-workflows-spec.md`, `workflow-state-machine-screen-map.md`

---

## 1. Shared Job Lifecycle

Every long-running workflow in ArgyllUX is a `Job`.

### 1.1 Common states

| State | Meaning |
|---|---|
| `Draft` | Started but not ready to run |
| `Ready` | Valid to continue |
| `Waiting to Print` | Output exists but has not been printed |
| `Printed` | Print confirmed |
| `Drying` | Timer or hold state before measurement |
| `Ready to Measure` | Instrument/setup is the next step |
| `Measuring` | Active chart or spot reading |
| `Review` | Results exist and a decision is needed |
| `Completed` | Intended output accepted |
| `Paused` | User paused intentionally |
| `Blocked` | External dependency missing or invalid |
| `Needs Attention` | Data or outcome needs review |
| `Superseded` | Replaced by newer accepted output |
| `Archived` | Historical but not active |

### 1.2 Shared rules

- Any non-terminal job may be paused.
- Jobs resume from the last good checkpoint.
- Drying and measurement progress are durable states, not reminders only.
- A job may spawn follow-up jobs.
- A newer accepted profile or calibration does not silently erase history.
- Instrument lock semantics apply only during active measurement steps.

---

## 2. Workflow Organization

The product uses six top-level routes, but workflows are goal-first actions that can be launched from `Home`, `Printer Profiles`, `Troubleshoot`, `Inspect`, or `B&W Tuning`.

### Core front-door workflows

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

`Inspect` is an analysis space, not a competing workflow label. Its actions are described in `05-advanced-inspection.md`.

---

## 3. Profile-Creation and Library Workflows

### 3.1 New Profile

**Goal:** Create a new printer profile from measured chart data.

**Entry points:**

- `Home`
- `Printer Profiles`
- `Settings > Printers / Papers` context handoff

**Key rule:** the user starts from `New Profile`, not from "set up a configuration." Printer, paper, and print settings are gathered inside the flow.

#### Functional stages

1. Select or create printer
2. Select or create paper
3. Choose print settings and measurement assumptions
4. Plan target
5. Generate target files
6. Print unmanaged
7. Dry / stabilize
8. Measure target
9. Build profile
10. Review results
11. Publish, keep as draft, or compare later

#### Typical state sequence

`Draft -> Ready -> Waiting to Print -> Printed -> Drying -> Ready to Measure -> Measuring -> Review -> Completed`

#### ArgyllCMS command sequence

1. `targen`
2. optional `printcal`
3. `printtarg`
4. `chartread` or `scanin`
5. `colprof`

#### Outputs

- target files
- measurements
- ICC profile
- initial verification summary
- stored printer/paper/settings context

#### Follow-up actions

- `Verify Output`
- `Improve Profile`
- `Rebuild`
- `Match a Reference`
- `Troubleshoot`

---

### 3.2 Improve Profile

**Goal:** Improve an existing profile with better or more targeted data.

**Critical note:** this is not the Argyll `refine` command. It is a supplemental measurement and rebuild workflow.

#### Supported improvement strategies

- add more patches
- target neutrals
- target a weak hue range
- add critical colors from image or spot samples
- rebuild with revised assumptions

#### Functional stages

1. Select base profile
2. Review prior verification and findings
3. Choose improvement strategy
4. Plan supplemental target
5. Generate, print, dry, and measure
6. Rebuild profile
7. Compare old vs new
8. Accept one, keep both, or continue iterating

#### ArgyllCMS command sequence

Same build pipeline as `New Profile`:

- `targen`
- optional `printcal`
- `printtarg`
- `chartread` or `scanin`
- `colprof`

#### Outputs

- supplemental measurements
- revised profile version
- before/after comparison

#### Best-fit reasons to use

- neutrals are weak but the profile is otherwise usable
- one hue family needs more support
- the current profile is decent and you want to improve it instead of starting over

---

### 3.3 Import Profile

**Goal:** Bring an existing ICC profile into the library as a first-class `Printer Profile`.

#### Functional stages

1. Select ICC file
2. Parse metadata and tags
3. Attempt to match printer, paper, and print settings context
4. Mark the context as known or unknown
5. Save profile into the library
6. Optionally open in `Inspect` or run `Verify Output`

#### Outputs

- imported profile object
- parsed metadata
- context status

#### Required rules

- If the original print context cannot be recovered, label it `Printer & Paper Settings Unknown`.
- Imported profiles remain usable for inspection, comparison, and verification.
- Imported profiles do not become trusted automatically.

---

### 3.4 Import Measurements

**Goal:** Bring external measurement data into the app as reusable evidence.

#### Functional stages

1. Select `.ti3` / CGATS or supported tabular data
2. Preserve original file and normalize internal representation
3. Record assumptions and provenance
4. Let the user choose the immediate intent:
   - inspect
   - compare
   - verify
   - improve profile
   - rebuild
   - troubleshoot
5. Open the correct destination with the imported evidence attached

#### Outputs

- imported measurement set
- mapped patch identity / location basis
- derived findings where possible

#### Required distinction

`Import Measurements` is not `Import Profile`.

- `Import Profile` = finished ICC
- `Import Measurements` = raw evidence for analysis and workflow decisions

---

### 3.5 Advanced Assets Inside Printer Profiles

These are not front-door workflows, but they remain first-class advanced capabilities inside `Printer Profiles`.

#### Device Links

- built with `collink`
- used for known source-to-destination transform paths

#### Calibrated Exports

- use `applycal`, `printtarg -K`, `printtarg -I`, `chartread -I`, or related deployment logic
- meant for compatibility paths where calibration handling is awkward

#### Model Profiles (MPP)

- advanced Argyll model-based profile outputs
- not a primary nav label
- explained once in plain language, then kept in the advanced area

---

## 4. Verification and Maintenance Workflows

### 4.1 Verify Output

**Goal:** Decide whether current output is still trustworthy and what to do next.

#### Why this exists

Users do not verify just to admire numbers. They verify to decide whether to keep trusting a profile, recalibrate, rebuild, improve the profile, or troubleshoot a real issue.

#### Functional stages

1. Choose basis of verification
2. Reuse existing evidence or create a fresh verification print if needed
3. Compare profile and measurements
4. Interpret findings
5. Recommend the least-destructive next action

#### Verification bases

- profile vs dedicated verification chart
- profile vs imported measurements
- current measurements vs trusted baseline
- profile fit against source measurements

#### ArgyllCMS commands

- `colverify`
- `profcheck`
- `mppcheck` when relevant

#### Outputs

- verification result
- last verification date
- verified against file
- relevant print settings snapshot
- delta E summary
- recommended next action

#### Common next actions

- accept current state
- `Improve Profile`
- `Recalibrate`
- `Rebuild`
- `Troubleshoot`

---

### 4.2 Recalibrate

**Goal:** Restore the printer to a previously trusted calibrated state without rebuilding the whole profile unless necessary.

#### Product meaning

`Recalibrate` is for maintenance-sized drift where a known-good calibration baseline exists and the workflow supports calibration recovery.

#### Functional stages

1. Select profile / context and baseline calibration
2. Generate or load wedge target
3. Print and dry
4. Measure wedge
5. Compare against prior calibration expectation
6. Accept or reject the recalibration result

#### ArgyllCMS commands

- `printcal -r`
- `printcal -e` when verifying the calibration state

#### Outputs

- calibration asset or verification record
- linked update to the current trust chain

#### When not to recommend first

- wrong media setting
- unmanaged printing mistake
- imported profile with no meaningful calibration history
- printer/workflow type where recalibration is known to be of limited value

---

### 4.3 Rebuild

**Goal:** Create a new characterization result because recalibration is not enough or the underlying assumptions changed.

#### Good reasons to rebuild

- recalibration did not restore trust
- measurements are suspect and must be re-done
- print settings changed materially
- the prior profile was imported and not well supported by evidence
- the workflow needs a genuinely new profile rather than maintenance

#### Functional stages

1. Choose profile or context to rebuild from
2. Reuse or revise prior recipe
3. Generate / print / dry / measure
4. Build new profile
5. Compare to prior version
6. Publish or keep as alternate

#### ArgyllCMS command sequence

Same as `New Profile`, with optional reuse of prior measurement strategy:

- `targen`
- optional `printcal`
- `printtarg`
- `chartread` or `scanin`
- `colprof` or `mppprof` where relevant

#### Outputs

- new profile version
- explicit comparison against the prior version

---

## 5. Reference-Matching Workflow

### 5.1 Match a Reference

**Goal:** Make the current output behave more like another measured reference condition.

This is where the Argyll `refine` command belongs conceptually.

#### Functional stages

1. Define the reference
2. Measure the current output
3. Compare mismatch
4. Build correction layer or revised transform path
5. Reprint and remeasure
6. Iterate until acceptable or no longer worthwhile

#### ArgyllCMS commands

- `colverify`
- `refine`
- `collink`
- `colprof`
- `revfix` where relevant

#### Outputs

- correction asset or revised profile path
- match history across iterations

#### Important product rule

`Match a Reference` is not the same thing as `Improve Profile`.

- `Improve Profile` makes the profile better at its own job
- `Match a Reference` intentionally pushes the output toward another target condition

---

## 6. Troubleshoot and Issue Case Workflow

### 6.1 Troubleshoot

**Goal:** Start from a symptom and route the user to the right corrective path.

This flow always has the option to save or continue as an `Issue Case`.

#### Entry symptoms

- neutrals too warm / cool
- specific color range is off
- prints too dark / light
- B&W cast or rough ramp
- profile used to be good, now off
- verification failed or looks suspicious
- paper / media setting issue
- measurement / instrument issue

#### Functional stages

1. Choose symptom
2. Gather evidence
3. Import or link existing measurements if available
4. Run evidence gates
5. Present likely causes and recommended next actions
6. Save or update `Issue Case`
7. Spawn follow-up jobs as needed

#### Outputs

- `Issue Case`
- ranked likely causes
- evidence-backed findings
- linked follow-up jobs

#### Persistence rule

Any troubleshooting flow can be saved as an `Issue Case`, and any open `Issue Case` can continue spawning work until the user marks it resolved or superseded.

---

## 7. Inspect-Adjacent Workflows

### 7.1 Spot Measure

**Goal:** Take quick live readings for diagnosis, comparison, or paper/neutral checks.

#### Functional stages

1. Select instrument mode
2. Calibrate instrument if needed
3. Read spot or repeated spots
4. Optionally compare to a saved reference
5. Save reading or send it into `Inspect` or `Troubleshoot`

#### ArgyllCMS commands

- `spotread`

#### Typical uses

- paper white check
- black patch check
- repeated-read stability check
- quick neutral comparison

---

### 7.2 Compare Measurements

**Goal:** Compare two or more measurement sets directly.

#### Functional stages

1. Select measurement sets
2. Align assumptions and patch-matching basis
3. Compute comparison
4. Review summary plus derived findings
5. Open `Inspect > Measurements` or continue into `Troubleshoot`

#### ArgyllCMS commands

- `colverify`
- `profcheck` when comparing profile prediction to measurements

#### Output expectations

The product should interpret the data into useful findings, not just raw tables:

- measured vs target
- measured vs baseline
- neutral drift
- hue-band weakness
- endpoint shifts
- outlier clustering

---

## 8. B&W Tuning Workflow

### 8.1 B&W Tuning

**Goal:** Improve monochrome output quality through neutrality, tone, and correction workflows that are distinct from standard color-profile creation.

#### Functional stages

1. Select printer, paper, and monochrome path
2. Choose wedge / test image / evaluation target
3. Print and dry
4. Measure wedge or evaluation target
5. Analyze neutrality, tonal smoothness, and shadow behavior
6. Store correction or validation result

#### ArgyllCMS commands

- `targen`
- `printtarg`
- `chartread` or `scanin`
- `printcal`
- `colverify`
- `refine` where a correction layer makes sense

#### Outputs

- grayscale-oriented calibration or correction assets
- validation history
- linked notes about visual and measured outcome

#### Guardrail

Do not describe this as a generic same-channel-count monochrome ICC workflow if Argyll does not actually provide that path.

---

## 9. State-Transition Rules

### 9.1 Print-dependent jobs

Any workflow involving printed output must show visible print and dry/stabilize states.

### 9.2 Measurement checkpointing

Measurement jobs must checkpoint:

- current strip / row / patch
- accepted reads
- re-read queue
- instrument assumptions

This is grounded in `chartread -r` and related resumable behavior.

### 9.3 Trust-chain updates

When a new profile, calibration, or verification result becomes accepted:

- the old one remains in history
- the new one becomes active only through explicit acceptance
- the profile detail updates its verification summary and state

### 9.4 Issue Case persistence

`Issue Case` remains open until resolved or superseded, even if it spans multiple jobs and routes.

### 9.5 Reuse of valid evidence

The application should prefer reuse before needless work:

- verify against existing files when valid
- compare against trusted baselines
- rebuild from valid measurements
- improve before replacing blindly

---

## 10. Concurrency Model

The application should be comfortable with multiple active jobs.

### Required behavior

- multiple jobs may be active
- only one job at a time owns an instrument during active measurement
- drying jobs do not block other jobs
- users can jump between jobs without losing local UI state
- background computations should still surface as visible job states where relevant

---

## 11. Cross-References

| Document | Relationship |
|---|---|
| `00-product-overview.md` | Product boundaries, terminology, and domain model |
| `01-information-architecture.md` | Navigation model and route structure |
| `03-screen-specs.md` | Screen layouts for jobs, profile detail, Issue Cases, and Inspect |
| `04-decision-engine.md` | Symptom routing and evidence interpretation used by Troubleshoot |
| `05-advanced-inspection.md` | Detailed Inspect-route behavior |
| `06-ui-copy-and-controls.md` | Canonical action names and control copy |
