# Code Review Checklist

## Diagnostics, Privacy, And Observability

For changes touching durable workflows, bridge calls, command execution, persistence, export, user-visible failures, or public-path behavior changes:

- Confirm the implementation emits a structured diagnostic event or explicitly explains why one is not useful.
- Confirm same-class public paths are not left silently uninstrumented.
- Confirm private data is not recorded in global diagnostics: file contents, measurement contents, ICC/profile bytes, CGATS rows, user notes, arbitrary stdout/stderr, hostnames, usernames, serial numbers, device identifiers, network information, and full filesystem inventories.
- Confirm command output remains in CLI Transcript unless the user explicitly chooses to include it in an export.
- Confirm exported diagnostics are redacted by default and suitable for public issue reports.
