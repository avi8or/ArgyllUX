# ArgyllUX

ArgyllUX is an open-source desktop application for printer profiling and print troubleshooting built around ArgyllCMS.

This repository currently holds the product specification and release/legal documentation for the project.

## Intended Distribution Model

- ArgyllUX code in this repository is intended to be released under `AGPL-3.0-or-later`.
- The default product flow is:
  - scan for an existing local ArgyllCMS installation
  - let the user choose an existing install, or
  - guide the user to the official upstream ArgyllCMS download and setup flow
- ArgyllUX does not bundle or mirror ArgyllCMS by default.
- ArgyllUX is not affiliated with or endorsed by ArgyllCMS or its author.

## Licensing

- Repository code: [LICENSE](LICENSE)
- Project distribution guidance: [LEGAL.md](LEGAL.md)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## Local-Only Dev Files

Developer-local agent and plugin folders, plus local Argyll reference docs under `docs/argyll-reference/`, are intentionally not tracked in git.
