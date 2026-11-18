# Proposed post-quantum provider: AWS-LC

Status: dependency integration approved by the user on 23 October 2026.
This records the approved candidate and acceptance gates; it does not claim an
installed provider or post-quantum messaging. Provider activation still requires
the native integration and tests below.

## Concrete candidate

- Upstream: https://github.com/aws/aws-lc
- Proposed initial version: v5.11.0, released 1 October 2026.
- Exact commit: `fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6`.
- Required primitives: ML-KEM-1024 and ML-DSA-87, documented in this release.
- Platform fit: upstream lists Android aarch64 and iOS aarch64 as CI-tested.
- Integration: native libcrypto, narrowly wrapped through the existing Android/iOS
  platform-channel boundary. No cloud service or AWS account is necessary.
- License: preserve the complete upstream LICENSE and component notices. Do not
  describe the library's mixed historical notices as one blanket MIT license.

## Proposed integration boundary

Use a namespaced static build so it cannot collide with crypto symbols already
embedded by other plugins. Pin source and build inputs, keep outputs reproducible,
and record checksums and license notices with generated binaries. Never download
an unversioned binary during app startup.

Expose only key generation, encapsulate/decapsulate, sign/verify, capability/version
reporting, and destruction of native secret buffers. Validate every input and output
length on both sides of the platform bridge. Keep private material out of exceptions,
logs and SharedPreferences; minimize copies and document platform-channel copies.

The existing `PqKem`/`PqSigner` adapters remain unavailable until the corresponding
native provider, vectors and both platform builds pass. Unsupported platforms fail
explicitly. Do not replace an unavailable operation with fabricated crypto or a
silent classical fallback.

Provider integration does not automatically enable PQ messaging. That also requires
authenticated distribution of PQ public keys, protocol-version negotiation,
downgrade protection, fresh session/reseed design, key rotation/revocation,
backward compatibility and an external review of the composition. A 66-character
classical ID alone does not authenticate an additional PQ identity bundle.

## Acceptance gates

1. Review the pinned release, security policy, licenses and known issues.
2. Build Android ARM64 and iOS device/simulator targets without symbol collisions;
   explicitly decide the status of Android x86/ARM32 and Windows rather than claiming
   they are covered by upstream ARM64 testing.
3. Run published known-answer vectors and cross-platform encapsulation/signature
   interoperability; include malformed lengths, corrupt ciphertext, verification
   failure, randomness failure and repeated lifecycle tests.
4. Verify capability checks, no secret logging, native buffer cleanup and release
   artifact provenance; measure size, latency, memory and battery on real devices.
5. Keep protocol activation gated until the authenticated key-distribution and
   migration design has independent review.

The normal pinned source build must not be marketed as a FIPS-validated app or
module. Validation applies to specific modules/builds and their conditions, not
automatically to an application that links cryptographic code.

## Alternatives considered

| Candidate | Findings |
|---|---|
| AWS-LC | Supports both requested primitive families; documented Android/iOS ARM64 CI; recommended candidate for the native provider |
| liboqs | Broad algorithm support, including NTRU, but upstream explicitly warns against relying on it for production or sensitive data; unsuitable as the default for the requested production product |
| libcrux | Strong verification work, but upstream describes prerelease maturity and the limits of verified modules; warrants evaluation with maintainers before adoption |
| Unverified pure-Dart PQ package | Language convenience is insufficient evidence for the threat model; no dependency selected on that basis |

## Primary sources checked

- Release: https://github.com/aws/aws-lc/releases/tag/v5.11.0
- Pinned primitives: https://github.com/aws/aws-lc/blob/v5.11.0/crypto/fipsmodule/PQREADME.md
- Platform policy: https://github.com/aws/aws-lc/blob/main/README.md
- Build/integration: https://github.com/aws/aws-lc/blob/main/BUILDING.md and https://github.com/aws/aws-lc/blob/main/INCORPORATING.md
- License: https://github.com/aws/aws-lc/blob/v5.11.0/LICENSE
- liboqs warning: https://github.com/open-quantum-safe/liboqs#limitations-and-security
- libcrux maturity/verification: https://github.com/cryspen/libcrux and https://cryspen.com/post/strengths-and-limitations/
