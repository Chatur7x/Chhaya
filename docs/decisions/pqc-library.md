# Decision: Post-quantum crypto library (`pqcrypto`)

- **Date:** 2026-10-09
- **Status:** Accepted — supersedes the Part 5 placeholder-only approach
- **Applies to:** Part 5 (Post-Quantum Hybrid KEX)

## Context

Part 5 shipped `lib/core/crypto/pqc/` as audit-gated placeholders that
throw `PqcUnavailableException`. Two paths were offered: approve a vetted
dependency, or fund an audit of a from-scratch FIPS 203/204 implementation.

The frozen stack ships no PQC primitive, and writing ML-KEM/ML-DSA by hand
would violate master rule §2.10 (only audited primitives may be used).

## Decision

Use the pure-Dart **`pqcrypto`** package.

## Rationale

| Property | Why it matters |
|---|---|
| No FFI | No native compilation; no `ndk`, no ABI breakage across Android/iOS/Windows |
| Pure Dart | Builds everywhere Flutter builds, including where the local dev host and CI runners differ |
| Auditable | Reviewable Dart source rather than an opaque binary |
| NIST vectors | Validated against FIPS 203/204 known-answer tests |

FFI-free matters most here: the repo already cannot verify an Android
build locally (no SDK on host), so a native toolchain would add another
unverifiable axis.

## Consequences

- `pqcrypto` is added to `pubspec.yaml` when Part 5 work resumes.
  Adding it is a dependency change, so it needs explicit approval at that
  point even though the library itself is now chosen.
- ML-KEM-1024 and ML-DSA-87 become real rather than throwing.
- Part 5 moves from "audit-gated placeholder" toward real readiness.

## Revisit condition

If the Part F3 benchmarks show unacceptable performance or binary-size
cost from the pure-Dart path, revisit **oqs** (liboqs via FFI). F3 is the
designated place that decision gets evidence.