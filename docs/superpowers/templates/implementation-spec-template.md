# Feature Name Spec

## Purpose

State the product or engineering problem in one short paragraph.

## Scope

List the user-visible and system-visible behavior included in this work.

## Non-Goals

List behavior this work intentionally leaves out.

## Architecture

Describe ownership, source-of-truth boundaries, and public interfaces.

## Diagnostics, Privacy, And Observability

State which durable workflows, bridge calls, command execution paths, persistence paths, exports, user-visible failures, or public behavior changes need diagnostics.

State which private data must not be recorded. Include file contents, measurement contents, ICC/profile bytes, CGATS rows, user notes, arbitrary stdout/stderr, hostnames, usernames, serial numbers, device identifiers, network information, and full filesystem inventories when relevant.

State what will be emitted as privacy-safe events, what will remain only in job-scoped CLI Transcript, and what export redaction must prove.

## Testing

List unit tests, integration tests, build/typecheck commands, and manual smoke checks.
