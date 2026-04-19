# ArgyllUX Legal and Distribution Notes

This document records the project's intended release model and the constraints it should follow. It is practical project guidance, not legal advice.

## 1. ArgyllUX License

ArgyllUX should be released as `AGPL-3.0-or-later`.

That matches the current project assumption that ArgyllUX is an open-source application built around ArgyllCMS rather than a closed-source commercial front end.

## 2. Default ArgyllCMS Integration Model

The default release path for ArgyllUX is:

1. On launch or setup, scan for an existing local ArgyllCMS installation.
2. If no installation is found, guide the user to the official upstream ArgyllCMS download and setup flow.
3. Allow the user to point ArgyllUX at the chosen installation.

This keeps the default distribution model simpler than redistributing ArgyllCMS directly.

## 3. Bundling Rules for This Project

The project should assume:

- no ArgyllCMS source or binaries are bundled by default
- no ArgyllCMS binaries are mirrored from project-controlled servers by default
- any future release that bundles, mirrors, or patches ArgyllCMS must be treated as redistribution of ArgyllCMS itself

If a future release bundles or redistributes ArgyllCMS, that release should also:

- include the upstream ArgyllCMS license texts and retained notices
- provide the corresponding source or a compliant source-access path for the redistributed copy
- clearly mark any modifications to upstream ArgyllCMS
- avoid presenting a modified build as the unmodified official ArgyllCMS release

## 4. Naming and Marketing Rules

Allowed positioning for ArgyllUX:

- `Compatible with ArgyllCMS`
- `Works with a locally installed copy of ArgyllCMS`
- `Guided setup for ArgyllCMS`

Avoid:

- implying affiliation, approval, sponsorship, or endorsement by ArgyllCMS or Graeme Gill
- calling ArgyllUX the official ArgyllCMS app
- presenting a modified ArgyllCMS build as plain `ArgyllCMS`

If the project ever redistributes a materially modified ArgyllCMS build, the modified build should be clearly distinguished from upstream naming.

## 5. Documentation-Licensing Split

This project can involve two different licensing situations:

- ArgyllUX application/repository code and original project materials
- Argyll-derived documentation material, including any local copies kept under `docs/argyll-reference/`

The official ArgyllCMS documentation states that:

- ArgyllCMS software is released under AGPLv3
- ArgyllCMS documentation is released under GNU Free Documentation License 1.3

That means the application-license decision and the documentation-license obligations should be tracked separately.

## 6. Repo-Specific Notice

If local Argyll-derived reference docs are kept under `docs/argyll-reference/`, any redistribution of those derivative documentation materials should preserve attribution and remain consistent with the upstream documentation terms.

## 7. Upstream Sources Used for This Guidance

- ArgyllCMS documentation index: https://www.argyllcms.com/doc/ArgyllDoc.html
- ArgyllCMS commercial licensing page: https://www.argyllcms.com/commercialuse.html
- icclib / cgatslib licensing page: https://www.argyllcms.com/icclibsrc.html
