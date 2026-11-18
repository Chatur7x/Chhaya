# Decision: Post-quantum crypto provider (AWS-LC)

- **Date:** 2026-10-23
- **Status:** Approved dependency; native integration and platform acceptance checks in progress
- **Applies to:** Part 5 (Post-Quantum Hybrid KEX)

## Context

Part 5 initially shipped `lib/core/crypto/pqc/` as provider abstractions.
The user approved adding a pinned native library after reviewing the proposal.

The frozen stack ships no PQC primitive, and writing ML-KEM/ML-DSA by hand
would violate master rule §2.10 (only audited primitives may be used).

## Decision

Use the version-pinned AWS-LC native provider for ML-KEM-1024 and ML-DSA-87.
See [the detailed proposal and remaining acceptance gates](../pqc-provider-proposal.md).

## Rationale

| Property | Why it matters |
|---|---|
| Pinned upstream | Builds from an exact AWS-LC commit with a checked source archive hash |
| Narrow bridge | Exposes bounded primitive operations through native platform channels |
| Platform limits | Android ARM64 and iOS are targeted; unsupported ABIs report unavailable |
| Acceptance | KATs, native builds, and mobile builds must pass before release claims |

The local Windows workspace lacks Flutter, Android and Apple build tools, so
GitHub-hosted CI is required to verify Android and iOS native builds.

## Consequences

- The approved provider is integrated as a local Flutter plugin and stays
  unavailable unless its native self-check passes.
- This primitive provider does not activate PQXDH in identity distribution,
  key negotiation, ratchets, or live messaging.
- Device interoperability, benchmarking, release provenance, and independent
  protocol/security review remain outstanding.

## Revisit condition

Revisit only if required platforms cannot build or AWS-LC's maintained API,
security status, performance, or licensing changes materially.
