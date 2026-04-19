# Third-Party Notices

This file tracks the third-party materials that affect this repository and its intended releases.

## ArgyllCMS

ArgyllUX is built around ArgyllCMS, but this repository does not currently vendor ArgyllCMS source or binaries as part of the default project model.

- Upstream project: https://www.argyllcms.com/
- Upstream documentation index: https://www.argyllcms.com/doc/ArgyllDoc.html
- Upstream commercial licensing page: https://www.argyllcms.com/commercialuse.html

Project assumption for distribution:

- ArgyllUX works with a user-selected, locally installed copy of ArgyllCMS.
- ArgyllUX scans for an existing installation and otherwise guides the user to the official upstream install flow.
- If a future release bundles, mirrors, or patches ArgyllCMS, that release must add the upstream ArgyllCMS license texts and source-availability details to the release package.

## ArgyllCMS Documentation Materials

If local material is kept under `docs/argyll-reference/`, it is sourced from the official ArgyllCMS documentation.

- Author: Graeme Gill
- Upstream source: https://www.argyllcms.com/doc/ArgyllDoc.html
- Upstream documentation license, per upstream docs: GNU Free Documentation License, Version 1.3

Those documentation materials should be treated separately from the ArgyllUX application code when preparing releases or republishing docs. Local copies are intentionally excluded from git.

## Local-Only Development Assets

Developer-local agent and plugin folders are intentionally excluded from git and are not part of the published repository contents.
