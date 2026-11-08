# Spec: Chhaya vNext — Hybrid Post-Quantum Session Establishment & Post-Restore Re-establishment

- **Status:** Proposed spec. Not implemented. Not release-verified. **Do not enable by default.**
- **Date:** 2026-11-08
- **Author:** specifier (from researcher BEGIN_SPEC_INPUT, verbatim) — repo `D:\Projects\PROJ16`
- **Provenance:** All protocol boundaries in this document derive from the `BEGIN_SPEC_INPUT` research block. Nothing here overrides it. Where a byte-level or operational detail had to be fixed to make the spec implementable, it is marked **SD-n** (spec decision, pending external review). Where the research block was incomplete, it is marked **OQ-n** (open question, blocks implementation steps as noted). No cryptography is invented in this document.
- **Hard gate:** Independent external cryptographic review (protocol composition, negotiation/downgrade state machine, resync extension, transcript encoding, restore interaction) is a **hard gate before any default-on behaviour and before any user-facing "post-quantum" or "secure restore" claim**. No interim claims are permitted. See §7.
- **Do not:** flip any status in `docs/feature-verification-127.csv` or `docs/delivery-checklist.md` as part of this spec or its implementation. Status changes are a lead/human decision after the gate.

---

## 1. Purpose & claims policy

### 1.1 Purpose

Specify the implementable, testable design for:

1. **Hybrid PQ session establishment ("v2 sessions")** — PQXDH (Signal PQXDH rev 3) with documented Chhaya deviations, for direct and group conversations.
2. **Post-restore session re-establishment ("resync")** — replacing today's unsafe deterministic session restart after an account restore, per the pinned failure in `test/unit/database/restore_resume_test.dart`.
3. **Fresh PQ secrecy v1** — a one-way hash-step chain with sparse ML-KEM-1024 reseed. Explicitly **not** SPQR.
4. **Backend prekey infrastructure** — public-only signed and one-time prekey distribution with atomic one-time pop.

### 1.2 Claims policy (binding until the §7 external-review gate passes)

**Forbidden user-facing claims (hard-fail strings, any UI/store/marketing/README/SECURITY.md/CSV prose):**

- "post-quantum secure messaging", "post-quantum encryption", "post-quantum security", "quantum-proof", "quantum-safe messaging"
- "secure restore", "safe restore", "guaranteed session recovery"
- "SPQR" used as a current feature/property (the reseed design is explicitly *not* SPQR; see §3.9)
- "audited", "independently reviewed", "triple ratchet with PQ", "FIPS-validated app/module"
- Any claim implying PQ on Windows, iOS runtime behaviour, x86 Android ABIs, or non-Android-arm64 PQ
- Any claim implying multi-device semantics (out of scope; see §7)
- Any default-on/availability claim before the gate

**Allowed (maximum ambition before the gate):**

- Engineering/internal documentation: "Hybrid PQXDH session establishment (experimental)", "ML-KEM-1024 via AWS-LC v5.11.0 (pinned commit `fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6`)".
- User-facing, only if the build actually gates the feature and the flag is visible in settings: "Experimental: hybrid post-quantum key establishment on supported devices (Android arm64). Not independently reviewed yet. Messaging security is not claimed to be post-quantum."
- Classical-only sessions (e.g. Windows): "Classical encryption only — not quantum-resistant" (persistent, visible flag; see WS6).
- Status reporting: "Not release verified" everywhere a checklist/CSV mentions the PQ rows.

**After the gate passes**, claims may be upgraded only by a lead/human decision that also updates `docs/delivery-checklist.md`, `docs/feature-verification-127.csv`, and this file's claims table. This spec does not pre-authorize any wording.

### 1.3 Claims mapping to feature-verification-127.csv (by id, name)

| CSV id | Row name | Allowed state after this work | Claim allowed pre-gate |
|---|---|---|---|
| 1 | E2EE text chat | stays `NOT RELEASE VERIFIED` / `partially implemented` | "classical direct path exists; PQ hybrid session establishment experimental" |
| 19 | ML-KEM-1024 | stays `partially implemented` | primitive availability ≠ PQ messaging |
| 20 | ML-DSA-87 | stays `partially implemented` | same; production signing use still pending review |
| 21 | Hybrid PQXDH | stays `partially implemented` | "scaffold replaced by experimental implementation behind flag; not release verified" — never "works / secure" |
| 22 | Dual-KEM | stays `partially implemented` (placeholder) | out of scope; no dual-KEM handshake claims ever in this work |
| 23 | Triple Ratchet | stays `partially implemented` | "hash-step chain + sparse reseed under review; not SPQR; no PQ ratchet claim" |
| 24 | SPQR | stays `partially implemented` | **forbidden to name/claim SPQR as present**; true SPQR blocked (see §3.9, §7) |
| 25 | Skipped-key cache | stays `implemented but unverified` → re-verify limits (criterion 13) only | "bounds enforced in code and tests; device acceptance pending" |
| 77 | Encrypted backup | stays `assessment pending` | backup ≠ secure restore; no "secure restore" wording until gate |
| 80 | Account restore | stays `NOT RELEASE VERIFIED` | "resync redesign in progress; no restore-security claim" |
| 81 | Multi-device restore | out of scope | none — must not be implied |

### 1.4 Claims mapping to delivery-checklist.md rows (by row name)

| Checklist row | Effect of this spec's work | Claim allowed pre-gate |
|---|---|---|
| Classical cryptography | unchanged; review still pending | "not independently reviewed" |
| Post-quantum primitives | Android arm64 evidence continues; iOS vectors pending; Windows absent | "AWS-LC integrated; iOS runtime unverified; Windows no PQ" |
| PQ hybrid/session bootstrap | this is the core of this spec; moves from "Scaffolded" to "implemented behind flag, review pending" | never "done"; stays pre-release |
| PQ ratchet | hash-step chain + sparse reseed only; not SPQR | "deterministic epoch chain replaced by hash-step chain under review" |
| Dual-KEM/NTRU | untouched placeholder | none |
| Encrypted backup | UX to re-establish sessions after restore is delivered (invisible resync) | no "secure restore" wording; device tests pending |
| External audit | **the hard gate** (§7) | "not commissioned / pending" |
| Multi-device pairing/revocation | untouched, out of scope | must not be implied by resync docs/UI |
| Monitoring/rate limits | new prekey endpoints are rate-limited (§4.4) | none |
| SQLCipher / Hardware key wrapping | dual-store of `session_generation` touches both | unverified device claims stay forbidden |

---

## 2. Threat model delta vs `docs/threat-model.md`

Base document: `docs/threat-model.md` (assets, trust boundaries, residual risks, required gates — all unchanged unless stated here). This section **adds** the following deltas. None of them relax existing boundaries.

### 2.1 Restore / rollback (new, critical)

- **Today:** after `replaceAccountSnapshot`, resuming a conversation re-derives a byte-identical initial session (same root, same chains, counter reset to 0, same SPQR seed) ⇒ key/nonce reuse for early messages. Pinned in `test/unit/database/restore_resume_test.dart` (pinned, not accepted).
- **Delta:** every account restore records a per-conversation `restore_generation` UUID. First post-restore contact runs a **full fresh PQXDH** (fresh SK ⇒ zero key/nonce reuse) and sends an authenticated `chhaya-resync-v1` ratchet message. Peer drops the pre-restore session and acknowledges after its own DH ratchet. Simultaneous restores tie-break on `max(restore_generation)`. Per-conversation monotonic `session_generation` is dual-stored in SQLCipher + platform keystore; rollback ⇒ forced resync.
- **Residual after fix:** a peer that never receives the resync retains a stale (but harmless-to-it) session; it cannot decrypt new traffic and will fail AEAD — acceptable, fail-closed.

### 2.2 Semi-trusted prekey server (new)

The server stores **public material only** and is authenticated + rate-limited, but it is semi-trusted:

- **DoS / withhold:** server can refuse bundle fetches or never serve PQ keys → availability failure (not confidentiality). Mitigation: rate limits, last-resort PQSPK fallback, client consent-gated classical-only fallback (never silent), key-change warning UX, low-count telemetry via `GET /prekeys/mine/count`.
- **Stale-serve:** server can serve expired or superseded prekeys → clients **must** enforce validity windows and signature verification; stale PQSPK ⇒ reject.
- **Targeted OPK drain:** server can pop one-time prekeys for a victim → last-resort PQSPK covers exhaustion; counts visible to the owner via `mine/count`.
- **Cannot forge:** bundles carry Ed25519 signatures from the identity signing key (§3.2); client always verifies; server-side signature checks are hygiene only.
- **Cannot force classical:** classical-only negotiation requires explicit user consent (mandatory on Windows); the fallback is domain-separated (§3.6) and flagged non-PQ; negotiation aborts rather than silently downgrades.
- **Metadata:** prekey fetch timing/volume is visible to the server (who is online, who is initiating). Not solved here. Recorded as residual metadata risk.

### 2.3 Last-resort prekeys (new)

When the one-time PQOPK pool is empty, the server serves the **last-resort PQSPK** within its validity window. Properties: reusable within the window (weaker freshness, still authenticated), expired ⇒ reject, always signed, counted separately in `mine/count`. Acceptance tests must cover both paths (§4.6 prekey obligations).

### 2.4 Downgrade (new)

Highest-common negotiation from explicit offer lists with **full offer echo**; both versions + selected suite bound into the SK salt via `SHA256(T)` and into AEAD additional data. AEAD failure ⇒ **hard abort**, never retry weaker. Classical-only only with explicit consent, logged, flagged non-PQ. Any silent weakening is a spec violation (criteria 2, 3, 4).

### 2.5 Group fork (new)

Group sends wrap per-recipient envelopes through the same codec path (`prepareEncrypt` in `ratchet_message_codec.dart`). A group where two members restored simultaneously could fork pairwise sessions. Tie-break on `max(restore_generation)` per pair (§3.7) plus the deterministic initiator rule (§3.1) converges all pairs to one session each. **Not solved here (residual):** group membership authentication remains trusted-server (see `docs/delivery-checklist.md` "Groups/admin roles"); resync does not authenticate group membership and must not be described as doing so.

### 2.6 Unchanged risks (explicit)

- Server sees account IDs, membership, timing, sizes, addresses — unchanged.
- Dart memory wiping is best-effort — unchanged; PQ secrets follow the same best-effort rule, plus `Csprng.wipe` on SK/epoch material where already applied.
- Free Render testing service sleeps and its database can expire — **prekey tables live in the same Postgres**; a free-tier expiry wipes prekeys silently. Client must tolerate missing/exhausted prekeys (abort + re-upload path) and operators must not treat Render free tier as production availability. No production claim may reference Render.
- Compromised unlocked device — unchanged.
- Active ratchet state is not in backups — unchanged; restore + resync is the designed recovery path (not a multi-device property).

---

## 3. Protocol definition

### 3.0 Identifiers, versions, suites

- Wire/protocol version: **v2** for the session establishment described here. Legacy classical sessions are "v1".
- Conversation id `conv_id`: existing conversation UUID string (lowercase canonical form).
- Suite identifiers are single bytes in the transcript and strings in APIs, e.g. `chhaya-pqxdh-v1` (PQ hybrid), `chhaya-classical-consent-v1` (consented classical fallback, domain-separated). Suites are listed in an explicit registry owned by this spec; adding a suite is a spec change.
- Curve: X25519 (RFC 7748) identity + EKA keys; Ed25519 (RFC 8032) identity **signing** key (separate key, already in repo).
- KEM: ML-KEM-1024 (FIPS 203) via AWS-LC v5.11.0 pin, Android arm64 only (this work), iOS build-verified but runtime unverified, software Windows plugin **does not exist** (no Windows target in `packages/chhaya_pqc`).
- Hash: SHA-256 (FIPS 180-4). Transcript hash `SHA256(T)`.
- AEAD: AES-256-GCM (unchanged wire format: `nonce‖ct‖tag` per `docs/crypto.md`).
- HKDF: RFC 5869, SHA-256 (`Hkdf.deriveKey` in `lib/core/crypto/primitives/hkdf.dart`).

### 3.1 Documented deviations from Signal PQXDH rev 3 (normative)

1. **Identity keys are X25519** for DH operations; a **separate Ed25519 identity signing key** (already in repo) signs prekeys. Upstream PQXDH uses a single identity key pair for both roles; Chhaya does not.
2. **HKDF with SHA-256** throughout (no HKDF-SHA-512).
3. **Canonical length-prefixed transcript** `T` (byte-level, §3.3) instead of upstream's ad-hoc encoding; `SHA256(T)` is the SK derivation salt and is also bound into AEAD AD.
4. **Derivation equation** (exact; resolved — source-verified against researcher BEGIN_SPEC_INPUT):
   `SK = HKDF-SHA256(ikm = 0xFF*32 ‖ DH1‖DH2‖DH3[‖DH4]‖SS, salt = SHA-256(Transcript), info = "Chhaya-PQXDH-v1"‖suite_string, len=32)`
   where DH1=DH(IKA,SPKB), DH2=DH(EKA,IKB), DH3=DH(EKA,SPKB), [DH4=DH(EKA,OPKB)] (omitted when no OPK used), SS = IKM-op envelope from MLKEM.Enc/Dec output, Transcript T = canonical length-prefixed encode(version_a‖version_b‖suite‖curve‖kem‖hash‖aead‖conv_id‖IKAe‖IKBe‖EKA‖SPKB.id‖PQPKB.id‖OPKB.id?‖CT‖role).
   `0xFF*32` denotes 32 bytes of 0xFF. The byte-exact layout of T (field order and widths) is normative in §3.3; the token list above is the researcher's canonical summary and binds the same inputs as §3.3. `suite_string` is the API string form of the suite (§3.0), e.g. `chhaya-pqxdh-v1`; the transcript carries `u8(selected_suite)` separately (§3.3). Implementations must use this ikm layout and this info string; nothing else is valid.
5. **Explicit offer lists + full echo** negotiation (§3.5); upstream PQXDH has no suite negotiation.
6. **Prekey distribution is server-mediated** with atomic one-time pop (§3.2, §4); upstream allows arbitrary distribution.
7. **Role assignment:** initiator = lexicographically smaller `'05'`-prefixed hex chhayaId (retains the repo's existing convention from `ratchet_message_codec.dart`, applied only in the v2 establishment).
8. **AEAD failure semantics are hard-abort** (§3.6), stricter than "ignore and continue".
9. **No deniability/post-compromise extras** beyond Double Ratchet; **no** Sesame/multi-device.

### 3.2 Prekey bundle format and validity windows

**Storage: public material only. The server never stores or receives private keys.** Bundles are JSON over HTTPS (repo convention), fields:

```
{
  "v": 1,
  "identity": { "x25519": "05<64hex>", "ed25519": "<64hex>" },
  "signedPreKey":    { "keyId": "<uuid>", "publicKey": "<64hex>",
                       "signature": "<128hex>", "notBefore": <ms>, "notAfter": <ms> },
  "pqSignedPreKey":  { "keyId": "<uuid>", "publicKey": "<3136hex ML-KEM-1024>",
                       "signature": "<128hex>", "notBefore": <ms>, "notAfter": <ms> },
  "oneTimePreKeys":   [ { "keyId": "<uuid>", "publicKey": "<64hex>",  "signature": "<128hex>" } ],
  "pqOneTimePreKeys": [ { "keyId": "<uuid>", "publicKey": "<3136hex>","signature": "<128hex>" } ],
  "reseedKemKey":    { "publicKey": "<3136hex>", "signature": "<128hex>" }
}
```

- **Signatures:** Ed25519 identity signing key over the canonical LP encoding (§3.3.1) of `keyId‖publicKey‖notBefore‖notAfter` (SD-1). Clients **MUST** verify every signature; server-side verification is a SHOULD (hygiene, never trusted).
- **Validity windows (SD-2, review-pending):**
  - `pqSignedPreKey` (last-resort): `notBefore`–`notAfter` = **7 days** max from upload. Expired ⇒ client rejects bundle.
  - `signedPreKey` (classical): window ≤ **30 days**; rotation grace for in-flight handshakes = **7 days** (old SPK honored for verification, never selected for new establishments after grace).
  - One-time prekeys: single-use; server purges unconsumed rows older than 30 days.
  - `reseedKemKey`: advertised and rotated with `pqSignedPreKey`.
- **Atomicity:** each bundle fetch pops **exactly one** EC one-time prekey and **exactly one** PQ one-time prekey in a single SQL transaction (`DELETE … RETURNING` with `FOR UPDATE SKIP LOCKED` selection). PQOPK preferred; if none available → last-resort `pqSignedPreKey` (counted, within window). See §4.3.
- **Rate-limited + authenticated:** all prekey routes behind `authMiddleware` and `consumeIpRateLimit` (§4.4).
- **Freshness:** clients reject bundles whose `pqSignedPreKey` is outside its window, whose signatures fail, or whose `keyId`s were seen before (client-side replay cache of prekey ids, 30 days).

### 3.3 Transcript encoding (byte-level) — SD-3, review-pending

#### 3.3.1 Length-prefix convention

`LP(x)` = `u16be(len(x)) ‖ x` for byte strings `x` whose length < 65536; `LP32(x)` = `u32be(len(x)) ‖ x` for larger payloads (ML-KEM ciphertexts). Integers that are semantically fixed-size are raw fixed-width big-endian (`u8` versions/suite/role, `u32be` epochs/counters). UUIDs are lowercase canonical 36-char strings under LP. No padding, no compression, no optional fields; unknown fields ⇒ abort.

#### 3.3.2 Transcript `T` (exact field order)

```
T = LP("Chhaya-PQXDH-v1")          # protocol label
  ‖ u8(protocol_version)          # v2 = 0x02
  ‖ u8(selected_suite)            # §3.0 suite registry
  ‖ u8(curve)                     # 0x01 = X25519
  ‖ u8(kem)                       # 0x01 = ML-KEM-1024
  ‖ u8(hash)                      # 0x01 = SHA-256
  ‖ u8(aead)                      # 0x01 = AES-256-GCM
  ‖ u8(initiator_version) ‖ u8(responder_version)   # both versions, §3.5
  ‖ LP(conv_id)
  ‖ ident_initiator_x25519(32) ‖ ident_responder_x25519(32)
  ‖ ident_initiator_ed25519(32) ‖ ident_responder_ed25519(32)
  ‖ EKA_initiator(32)             # ephemeral X25519 public key
  ‖ LP(spk_id) ‖ LP(pqspk_id)     # signed prekey ids
  ‖ LP(opk_id)                    # EC one-time prekey id, or LP("") if none
  ‖ LP(pqopk_id)                  # PQ one-time prekey id, or LP("") if last-resort used
  ‖ role                          # u8: 0x01 initiator, 0x02 responder
  ‖ LP32(CT_MLKEM)                # ML-KEM-1024 ciphertext (1568 bytes)
```

- `EKA` = ephemeral key-agreement public key. Both peers compute identical `T` from the exchanged flight (initiator builds it from its sent offer + received bundle; responder builds it identically from its received offer + its bundle). Any mismatch ⇒ derived SKs differ ⇒ AEAD fails ⇒ hard abort. This *is* the downgrade tripwire.
- `CT` is the ML-KEM encapsulation ciphertext toward the peer's prekey.
- `salt = SHA256(T)`; see §3.4.

### 3.4 Derivation equations (RFC 5869, SHA-256)

```
salt  = SHA256(T)
SK    = HKDF-SHA256(ikm = 0xFF*32 ‖ DH1‖DH2‖DH3[‖DH4]‖SS,   # OQ-2, resolved — source-verified against researcher BEGIN_SPEC_INPUT
                    salt = salt,                              # salt = SHA-256(Transcript T); T layout normative in §3.3
                    info = "Chhaya-PQXDH-v1" ‖ suite_string,  # API string form (§3.0)
                    len  = 32)
   # where DH1=DH(IKA,SPKB), DH2=DH(EKA,IKB), DH3=DH(EKA,SPKB),
   # [DH4=DH(EKA,OPKB)] (omitted when no OPK used),
   # SS = IKM-op envelope from MLKEM.Enc/Dec output.
   # Transcript T = canonical length-prefixed encode(
   #   version_a‖version_b‖suite‖curve‖kem‖hash‖aead‖conv_id‖IKAe‖IKBe‖EKA‖
   #   SPKB.id‖PQPKB.id‖OPKB.id?‖CT‖role)

# Consented classical fallback (domain-separated, never silent):
SK_fb = HKDF(ikm = DHs_classical,
             salt = salt,                                 # same T (contains suite + versions)
             info = "Chhaya-Classical-Fallback-v1" ‖ suite_byte,
             length = 32)

# Hash-step chain (NOT SPQR), §3.9:
seed_{n+1} = HKDF(ikm = seed_n, salt = <none/zero per Hkdf primitive convention>,
                  info = "Chhaya-SPQR-step-v1" ‖ u32be(n+1), length = 32)
epoch_key  = HKDF(ikm = seed_n, salt = <same convention>,
                  info = "Chhaya-SPQR-v1" ‖ u32be(n), length = 32)   # existing constant, unchanged

# AEAD additional data for every message under the session:
AD = header ‖ T                                          # SD-4, review-pending
```

- Group messages: AD additionally includes `['chhaya-group-body-v1', conv_id, messageId, sender]` as today; the v2 AD extends the existing `ratchet_message_codec.dart` construction (`_aad`) rather than replacing its semantics.
- HKDF `salt` omission follows the repo's existing `Hkdf.deriveKey` convention (`lib/core/crypto/primitives/hkdf.dart`, RFC 5869 §2.2: absent salt = HashLen zeros). Tests pin RFC 5869 vectors only for primitives already pinned; new derivations are pinned by self-consistency + review, not by invented vectors.
- Info strings above are normative. Any change ⇒ spec version bump.

### 3.5 Version negotiation state machine

Explicit offer lists. Both versions and the selected suite are bound into `T` (§3.3) ⇒ SK salt ⇒ AEAD AD (§3.4).

```
                 offers (supported suites)         offer echo
  INITIATOR ──────────────────────────────▶ RESPONDER
  INIT ──▶ OFFER_SENT ──▶ BUNDLE_SENT ──▶ SUITE_SELECTED ──▶ ESTABLISHED
                ▲              │                  │
                │              ▼                  ▼
                │           ABORT             ABORT
                └── (timeout/failure) ──────────┘
```

Rules (all normative):

1. Both parties send explicit `offers: [suite, ...]` with their protocol version in the first flight. Offers are not secret; they are echoed in full and bound into `T`.
2. **Highest-common:** each side computes `selected = max(priority)(offers_initiator ∩ offers_responder)` using the fixed registry order. The computation is a pure function of the two lists ⇒ both sides agree iff neither list was tampered with. No common suite ⇒ ABORT.
3. **Full offer echo:** the bundle-carrying flight echoes the received offer list byte-for-byte. Initiator verifies echo equality; mismatch ⇒ ABORT.
4. `T` binds `initiator_version ‖ responder_version ‖ selected_suite` (§3.3). Tampering with any offer/version/suite changes `T` ⇒ SK mismatch ⇒ AEAD failure ⇒ ABORT (§3.6). **There is no code path in which a weakened parameter set yields a usable session.**
5. **Classical-only is never silent.** It requires (a) capability probe = PQ unavailable on this build/platform (Windows always; other platforms on provider failure) and (b) explicit user consent via a blocking dialog with exact disclosure text, (c) `consented: true` recorded on the session, logged locally (and, if telemetry enabled, via existing metrics with no payload beyond the flag), (d) session flagged `nonPQ: true` and surfaced as "Classical encryption only — not quantum-resistant" in the conversation list/settings/export. Domain-separated derivation `"Chhaya-Classical-Fallback-v1"` (§3.4) prevents cross-protocol confusion with PQXDH sessions.
6. **AEAD failure ⇒ hard abort** (§3.6). No renegotiation-in-place; only an explicit new `chhaya-resync-v1` (§3.7) or fresh establishment may create a session.
7. Role rule: initiator = smaller `'05'`-hex chhayaId (§3.1.7). In a simultaneous-restore tie-break, roles stay as-is; only the conversation `restore_generation` is settled by max-uuid (§3.7).

### 3.6 Failure semantics (normative)

| Failure | Behaviour |
|---|---|
| Bundle signature invalid / keyId replay / expired PQSPK / prekey-id reused | Abort establishment. No session persisted. UI: "Couldn't verify this contact's keys." Log locally. |
| Offer echo mismatch / no common suite / unexpected suite byte | Abort. No session persisted. Log locally + counter metric. |
| ML-KEM decapsulation failure (provider reports error) | Abort. Wipe SK material. Never "retry with EC-only". |
| AEAD tag failure on any message under established session | **Hard abort the session**, wipe SK/chain material, surface "Message could not be authenticated", require explicit user action (or next resync) to re-establish. **Never** retry with a weaker suite, previous key, or skipped tag check. |
| One-time PQ prekey exhausted, last-resort in-window | Serve last-resort (§3.2); client counts it; UX nudge to top up (`mine/count`). |
| One-time exhausted **and** last-resort expired/missing | Abort + UI error + server-side operator alert (metric). |
| Network timeout/5xx during establishment | Abort; outbox retains draft; bounded retry with backoff; **retries never weaken parameters**. |
| `session_generation` rollback detected (§3.8) | Force resync; do not decrypt under stale generation. |
| Corrupt persisted session blob | Existing behaviour (`session_store.dart` throws StateError) — keep; never auto-create a deterministic replacement (that path is deleted, §5 WS3). |
| Consent-gate declined (user refuses classical fallback) | Abort; no session; conversation remains unsent; no silent default. |

### 3.7 Resync: `chhaya-resync-v1` message format, tie-break, session lifecycle

**Trigger:** after `LocalDatabase.replaceAccountSnapshot` (restore/rollback), the first post-restore contact with any peer runs a full fresh PQXDH before any user content, then sends `chhaya-resync-v1`. Offline peers receive it later via the existing store-and-forward path (§4.5). Pending/stuck messages are re-created from DB content with **new messageIds** after successful re-establishment (§3.7.5); users never see this; duplicates may appear at the peer (accepted tradeoff).

**Payload** (inside the normal encrypted ratchet envelope, `messageType` unchanged, content opaque to the server; payload is JSON):

```
{
  "type": "chhaya-resync-v1",
  "restore_generation": "<uuid v4>",   # per-conversation, recorded by replaceAccountSnapshot
  "session_generation": <uint64>,      # monotonic, §3.8
  "reason": "restore" | "rollback",
  "v": 1
}
```

**Peer behaviour on valid resync (AEAD-verified under the new session):**

1. Delete the pre-restore persisted session blob for that conversation (superseded by the fresh PQXDH session already established).
2. Perform its own DH ratchet step; its first outbound ratchet message under the new session **is the ack**. (Ack MAY carry `{"type":"chhaya-resync-ack-v1", ...}`; absence of a user message does not block ack.)
3. Sender treats any AEAD-valid message from the peer under the new session as ack. Until ack: no user-visible send from the initiator; UI shows nothing (invisible to users).

**Simultaneous restores (tie-break, normative):** both sides restored and both sent resync. Each side compares `restore_generation` (UUID compared as 16 raw bytes, i.e. memcmp order — equivalently, lexicographic order of the lowercase canonical string). **The conversation adopts `max(restore_generation)`**; the other side records the max as the conversation's `restore_generation` (both sides converge to the same value) and logs locally. Role assignment for the fresh PQXDH is unaffected (§3.1.7); the tie-break settles only the recorded generation, never the cryptographic session.

**Generation settling is idempotent:** re-processing a resync with an already-adopted (equal or smaller) generation is a no-op.

**3.7.5 Pending message re-creation (normative):** after ack, every stuck pending message for the conversation is re-created **from DB content** (never from the stale outbox envelope) with a fresh `messageId` (uuid), re-encrypted under the new session, and passed through the existing atomic outbox/retry machinery (`messaging_service.dart` `retryPending`). Original rows are retained as superseded for 30 days (forensics), then expired by the disappearing-content machinery; no new tombstones.

### 3.8 `session_generation` dual-store and rollback rules

- **Per conversation**, one monotonic `session_generation` (uint64).
- **Dual-stored** in (a) SQLCipher local DB (`kv` table key `session_generation/<conversationId>`, or a `conversations` column — WS3 fixes the concrete location; either satisfies this spec) and (b) platform keystore/keychain via `flutter_secure_storage` (key `session_generation.<conversationId>`).
- Written together, in order: keystore first, then SQLCipher; any crash between ⇒ on next open, missing keystore value with present DB value (or vice-versa) ⇒ **fail closed to force-resync**, never adopt the lower value silently.
- Incremented on every completed (acked) establishment/resync for that conversation.
- **Rollback ⇒ force resync:** if the DB value is lower than the keystore value (stale DB copy, flash-restore, corrupt migration, backup of DB only), the client MUST force a resync for that conversation before any decrypt/encrypt under the stale session.
- `restore_generation` is set once per restore per conversation by `replaceAccountSnapshot` (§5 WS3) and is not monotonic across restores (new random UUID each restore; `max()` only within simultaneous-restore settling).

### 3.9 Fresh PQ secrecy v1 — hash-step chain + sparse ML-KEM reseed (NOT "SPQR")

- v1 adds **one-way hash-step evolution** to the chain seed and a **sparse ML-KEM-1024 reseed**:
  - `seed_{n+1} = HKDF(seed_n, info="Chhaya-SPQR-step-v1" ‖ u32be(n+1))` (salt per §3.4 convention). One-way: compromising `seed_{n+1}` does not reveal `seed_n`.
  - **Sparse reseed every ~25 sends or 7 days, whichever first:** the sender encapsulates ML-KEM-1024 to the peer's advertised `reseedKemKey` (§3.2) and injects the shared secret via the existing `SpqrChain.reseed` (`lib/core/crypto/ratchet/spqr.dart`). Both sides wipe the injected PQ output after injection.
- **This is explicitly NOT "SPQR".** It must not be named, marketed, or described as SPQR, "Sparse Post-Quantum Ratchet", or "Triple Ratchet with PQ". The deterministic epoch derivation (`SpqrChain.chainKeyFor`) remains as-is for epoch key derivation within the skip window; the hash-step is an additional one-way wrapper on the seed.
- **True SPQR** (the Sparse Post-Quantum Ratchet construction with libcrux incremental KEM) is **blocked** on (a) libcrux incremental-KEM FFI integration and (b) external review. Neither exists. It must not be named or claimed anywhere in code comments, UI, docs, or this repo's claim surfaces. If/when it lands, it is a separate spec + gate.
- `SpqrChain.advanceEvery` stays 10; the ~25-send/7-day reseed cadence is independent of epoch advance and is a separate timer+counter tracked per session (persisted with session state).
- Reseed ciphertext rides the existing authenticated envelope flow as payload type `"chhaya-reseed-v1"` (ML-KEM ciphertext for the peer's advertised `reseedKemKey`); it is invisible to users (no event, no UI).
- `reseedKemKey` rotation rides the 7-day prekey rotation (SD-2). This is the research-specified design; strengthening it (e.g., ephemeral reseed KEM keys) is out of scope and requires researcher sign-off.

### 3.10 Double Ratchet limits and epoch keys

- Keep `maxSkip = 1000`, `maxSkippedTotal = 2000`, single-use skipped-key cache (`lib/core/crypto/ratchet/double_ratchet.dart`).
- **Epoch/skipped keys are derivable and usable only within the skip window.** Out-of-window or replayed skipped keys are discarded. Criterion 13 extends existing coverage.
- Skipped-key cache entries are consumed on first use (single-use) — unchanged, re-asserted by tests.

### 3.11 Migration and rollback rules

- **Lazy per-conversation v2 upgrade:** a conversation migrates on its first v2 send/establishment after upgrade. No bulk migration, no flag-day.
- **Legacy sessions persist receive-only** until the conversation reaches **50 v2 messages or 30 days** since first v2 message (whichever first), then the legacy blob is securely wiped.
- **Group path inherits via the same codec** (`prepareEncrypt`/`prepareDecrypt` flow) — no separate group handshake, no group-specific PQ design in this work.
- **`ratchet_message_codec.dart` `_state` (deterministic identity-ECDH establishment) MUST BE DELETED** in the same change that ships v2 establishment. Its tests (`test/unit/messaging/ratchet_message_codec_test.dart`) are rewritten to v2 expectations, not patched around.
- **`test/unit/database/restore_resume_test.dart` pinned tests are replaced** by byte-*inequality* assertions plus the resync integration tests (§6, criteria 7, 8). The "byte-identical initial session" pins are anti-goals.
- **Rollback (flag off):** disables v2 offers/establishment; persisted legacy sessions remain decryptable receive-only; v2 sessions, once established, remain decryptable (the v2 code path stays compiled). Rolling the app binary back to 14.0.1 orphans v2-established conversations — documented, unsupported; hotfix-flag-off is the supported rollback (§9.3).
- **No down-migration deletes data.** Prekey tables are inert when endpoints are disabled; they are never dropped by this work (§9.4).

---

## 4. Backend work items (`backend/server/`)

Conventions: TypeScript, Express, zod validation at the boundary, `authMiddleware`, `consumeIpRateLimit` + `pruneExpiredRateLimits` patterns (`src/rate-limit.ts`), `withTransaction` for atomicity, parameterized queries only, migrations appended as new entries in the `migrations` array in `src/db.ts` (index = version, checksummed; **append-only — never edit an existing statement**). Tests: `backend/server/test/*.test.cjs` run via `npm test` (`npm run build && node --test test/*.test.cjs`), exercised in CI (`.github/workflows/ci.yml`, backend job) and locally against Postgres.

### 4.1 Schema (new migration, appended)

```sql
CREATE TABLE IF NOT EXISTS prekey_signed (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('ec','pq')),
  key_id UUID NOT NULL,
  public_key TEXT NOT NULL,        -- hex; public only
  signature TEXT NOT NULL,         -- hex Ed25519 over canonical encoding (SD-1)
  not_before TIMESTAMPTZ NOT NULL,
  not_after TIMESTAMPTZ NOT NULL,
  is_last_resort BOOLEAN NOT NULL DEFAULT TRUE,   -- pq only
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, kind, key_id)
);
CREATE TABLE IF NOT EXISTS prekey_one_time (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('ec','pq')),
  key_id UUID NOT NULL,
  public_key TEXT NOT NULL,
  signature TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, kind, key_id)
);
CREATE INDEX IF NOT EXISTS idx_prekey_one_time_pop
  ON prekey_one_time (user_id, kind, created_at);
```

- No private material can be represented (lengths enforced by zod; public-only). `is_last_resort` rows are reusable within window; one-time rows are deleted on pop.
- `restore_generation` / `session_generation` live **client-side only**; no server schema change for them.

### 4.2 Endpoints (new routes in `src/routes.ts`, all behind `authMiddleware`)

| Method & path | Body / params | Behaviour |
|---|---|---|
| `POST /prekeys` | zod bundle of §3.2 (public only) | Validate shape, lengths, timestamps, Ed25519 signatures (SHOULD verify). Upsert `prekey_signed` rows (rotate in place), bulk-insert `prekey_one_time`. Reject any private-looking field ⇒ 422. |
| `GET /prekeys/:userId/bundle` | path param | **Atomic pop** (§4.3): returns identity (public), current `signedPreKey`, `pqSignedPreKey` (in-window; expired ⇒ 409 `pq_last_resort_expired`), one popped EC OPK + one popped PQOPK (or last-resort PQSPK fallback), `reseedKemKey`. Unknown target ⇒ 404. |
| `POST /prekeys/rotate` | `{ signedPreKey?, pqSignedPreKey?, reseedKemKey? }` | Upsert rotations; old rows retained for 7-day grace (§3.2), excluded from new bundles after grace; returns new `notAfter`. |
| `GET /prekeys/mine/count` | — | `{ ecOneTime: n, pqOneTime: n, pqLastResort: { present, notAfter }, signedAgeDays: { ec, pq } }` for the authenticated user. No other user's data. |

### 4.3 Atomic pop (normative SQL semantics)

In **one transaction** (same statement shape for `ec`):

```sql
WITH picked AS (
  SELECT key_id FROM prekey_one_time
  WHERE user_id = $1 AND kind = 'pq'
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE SKIP LOCKED
)
DELETE FROM prekey_one_time po USING picked
WHERE po.key_id = picked.key_id AND po.user_id = $1 AND po.kind = 'pq'
RETURNING po.key_id, po.public_key, po.signature;
```

If the PQ branch returns no row ⇒ serve in-window last-resort `pqSignedPreKey` instead; bundle records `lastResortUsed: true`. Two concurrent fetches pop distinct rows or one falls back to last-resort; both invariants are testable (§4.6 prekey obligations). `SKIP LOCKED` avoids serializing concurrent fetches behind a lock convoy.

### 4.4 Rate limits (normative minimums; tune with threat model)

Per keyed-HMAC caller identity (existing `consumeIpRateLimit`) **and** per-target-user budget for bundle fetches (SD-5):

- `POST /prekeys`: 30 / hour / user
- `GET /prekeys/:userId/bundle`: 60 / minute / caller-IP-HMAC **and** 120 / hour / target user
- `POST /prekeys/rotate`: 10 / hour / user
- `GET /prekeys/mine/count`: 120 / minute / user
- 429 responses carry `Retry-After` (existing pattern). All four routes also covered by global limits and `helmet`.

### 4.5 Restore interplay / store-and-forward

`chhaya-resync-v1` messages are **normal encrypted envelopes** flowing through existing `POST /messages` → `messages` table → `GET /messages/:conversationId` (`pendingDelivery` marking `delivered_at`). The server cannot distinguish resync from user content (content is an opaque envelope). No new server surface, no content inspection, no deliverability-guarantee change: an offline peer's resync is delivered when it next fetches, exactly like any envelope. Expired/duplicate envelopes follow existing retry semantics. **This is deliberate:** minimal server change, zero new metadata semantics.

### 4.6 Backend test obligations

New: `backend/server/test/prekeys.test.cjs`, `backend/server/test/prekeys-bundle.test.cjs`:

- Upload validation: rejects oversize/malformed/non-public fields; accepts valid bundle.
- Atomic pop: concurrent fetches (e.g., 20 parallel) pop distinct PQOPKs; exhaustion ⇒ last-resort; last-resort expired ⇒ 409; last-resort respects window boundary (injected clock or fake timers).
- Rate limits: 429 after threshold; `Retry-After` present; bucket keys are HMAC'd (no raw IPs persisted).
- `mine/count`: counts accurate after uploads/pops; no cross-user leakage.
- Rotation grace: old SPK verifiable but never served post-grace; new fetches serve rotated key.
- Store-and-forward: resync-type envelope round-trips unchanged through post/fetch (opaque-content assertion).

### 4.7 Explicitly not in backend scope

Session/ratchet crypto, `session_generation`, `restore_generation`, negotiation, AEAD, resync semantics — all client-side. Push-notification changes: none. Admin tooling: none (no private material exists to administer).

---

## 5. Client work items (workstreams)

Effort classes: **S** (≤1 day), **M** (1–3 days), **L** (>3 days). Android arm64 is the PQ target; Windows and iOS per gaps below. Every workstream: rollback = git revert + flag off; dev-test isolation via existing in-memory DB / `InMemorySessionStorage` patterns; no workstream may weaken existing tests.

### WS1 — Backend prekey infrastructure (§4)

- **Scope:** migration append, 4 endpoints, atomic pop, rate limits, zod schemas, backend tests (§4.6), `.env.example` note; operator note for Render/self-host parity (prekey expiry on free tier) in PR description — not in this file.
- **Affected files:** `backend/server/src/db.ts`, `backend/server/src/routes.ts`, `backend/server/test/prekeys*.test.cjs` (new), `backend/server/.env.example`.
- **Acceptance criteria:** §4.6 all green via `cd backend/server && npm test`; CI backend job green; lint clean.
- **Rollback / isolation:** endpoints behind env flag `PREKEYS_ENABLED` (default `false`); flag off ⇒ 503 `feature_disabled`, zero behaviour change for existing clients. No impact on messaging paths.
- **Effort:** M. **Depends on:** none.

### WS2 — Dart protocol helpers + negotiation (§3.1–3.6)

- **Scope:** suite registry + `selected = max(∩)` highest-common negotiation with offer-echo verification; `T` encoder (LP, byte-exact per §3.3); `SK`/`SK_fb` derivation per §3.4 (OQ-2 resolved, source-verified); AEAD AD extension (`header‖T`, SD-4); hard-abort semantics; capability probe (platform ⇒ suite availability); consent-gated classical fallback with `Chhaya-Classical-Fallback-v1` domain separation; structured local logging (no secrets).
- **Affected files:** `lib/core/crypto/pqc/pqxdh.dart` (rewrite in place, SD-6 — delete scaffold dead code), `lib/core/crypto/pqc/hybrid_kex.dart` (reuse `HybridKex.combine` only if it matches §3.4; otherwise fold and delete), `lib/core/crypto/primitives/hkdf.dart` (reuse unchanged), `lib/services/messaging/ratchet_message_codec.dart` (wire `T` into AD), `lib/core/crypto/ratchet/session_state.dart` (persist `nonPQ` flag, `consented`, `session_generation`).
- **Acceptance criteria:** criteria 1–5 green; `flutter analyze` clean; RFC 5869 primitive vectors still pinned (`test/unit/crypto/primitives_test.dart`) unchanged.
- **Rollback / isolation:** behind feature flag `chhaya_pq_hybrid_v1` (default off). Flag off ⇒ v2 code compiled but unreachable; v1 paths untouched.
- **Effort:** L. **Depends on:** WS1 (bundle endpoints for integration testing; unit tests may mock).

### WS3 — Resync + restore integration + test rewrites (§2.1, §3.7–3.11)

- **Scope:** `replaceAccountSnapshot` assigns/records per-conversation `restore_generation` (local DB schema version bump; nullable column or kv keys; UUID per conversation inside the same transaction); `session_generation` dual-store (SQLCipher kv + `flutter_secure_storage`, write order keystore→SQLCipher, fail-closed on mismatch); resync send-on-first-post-restore-contact; peer-side drop-old-session + ack-after-DH-ratchet; `max(restore_generation)` tie-break (16-byte memcmp, equivalent to lowercase-UUID memcmp); offline path via existing store-and-forward (no server change); stuck pending messages re-created from DB content with new messageIds after resync ack (reuse `messaging_service.dart` outbox logic, `messageId = uuidv4()`, content re-encrypted under the new session); invisible-to-users UX (no banner, no event); **delete `ratchet_message_codec._state`**; rewrite `test/unit/messaging/ratchet_message_codec_test.dart` to v2 expectations; rewrite `test/unit/database/restore_resume_test.dart` pins into byte-inequality + resync expectations.
- **Affected files:** `lib/core/database/local_database.dart` (schema + `replaceAccountSnapshot`), `lib/services/messaging/ratchet_message_codec.dart`, `lib/services/messaging/messaging_service.dart`, `lib/core/crypto/ratchet/session_state.dart`, `lib/core/crypto/ratchet/session_store.dart`, `test/unit/database/restore_resume_test.dart`, `test/unit/messaging/ratchet_message_codec_test.dart`, new `test/integration/resync_restore_test.dart`, new `test/integration/resync_simultaneous_restore_test.dart`.
- **Acceptance criteria:** criteria 7–11, 14 green; no remaining deterministic establishment path (`grep -n "deriveSharedSecret" lib/services/messaging/` hits only migrated v2 helpers); legacy receive-only window enforced by test.
- **Rollback / isolation:** flag `chhaya_pq_hybrid_v1` off ⇒ resync triggers never fire; restore behaves as today for legacy sessions — **except** `_state` deletion is unconditional (it is a security fix); legacy *persisted* sessions still decrypt. DB migration is additive-only (nullable column / new kv keys); no data rewritten.
- **Effort:** L. **Depends on:** WS2.

### WS4 — Tier-1 reseed (§3.9)

- **Scope:** hash-step chain wrapper (`seed_{n+1}` derivation) around `SpqrChain`; sparse reseed scheduler (counter ~25 sends + 7-day timer, persisted in session state; whichever first); encapsulate to peer `reseedKemKey` via existing authenticated envelope flow (payload type `"chhaya-reseed-v1"` carrying the KEM ciphertext, invisible to users); inject via `SpqrChain.reseed`; wipe PQ output post-injection; tests criterion 8.
- **Affected files:** `lib/core/crypto/ratchet/spqr.dart`, `lib/core/crypto/ratchet/session_state.dart`, `lib/services/messaging/ratchet_message_codec.dart` (reseed payload branch), new `test/unit/crypto/ratchet/spqr_step_reseed_test.dart`.
- **Acceptance criteria:** criterion 8 green; no code/comment/UI/claim names the v1 chain "SPQR" as a current feature (static grep gate, WS5); `SpqrChain.advanceEvery` unchanged.
- **Rollback / isolation:** reseed cadence gated by the same flag; disabling stops reseeds (sessions continue on the hash-step chain); no state corruption (reseed injection is append-only).
- **Effort:** M. **Depends on:** WS2, WS3.

### WS5 — Migration, feature flag, capability UI (§1, §3.11)

- **Scope:** flag `chhaya_pq_hybrid_v1` plumbing (dart-define; local default off; remote-config-ready); lazy per-conversation v2 upgrade on next send; legacy receive-only persisted blobs; drop-after-50-v2-messages/30d secure wipe; group path verified via existing codec; **non-PQ flag UI** (persistent "Classical encryption only — not quantum-resistant" badge on flagged conversations + settings entry; settings toggle to disable PQ hybrid for testing); claims-string static grep gate (`scripts/check_no_pq_claims.py`, recommended; blocking only on user-facing surfaces: `lib/`, `android/app/src/main/res`, `ios/Runner`, `web/` — `docs/` is lead-owned and excluded); `scripts/check_transcript_binding.py` static check (§6, required) wired into `.github/workflows/ci.yml` as a new step (lead applies the workflow edit).
- **Affected files:** settings/conversation UI files (discover via `grep -r "ratchet" lib/features lib/ui` during implementation), `lib/services/settings/` (discover), `scripts/check_transcript_binding.py` (new), `.github/workflows/ci.yml` (lead edit), `pubspec.yaml` (no new deps).
- **Acceptance criteria:** criterion 14 green; flag off restores legacy behaviour end-to-end (manual checklist + automated migration test); grep gate passes; legacy drop wipes blobs (test asserts secure-wipe invocation).
- **Rollback / isolation:** flag; UI badge hides when flag off; migration is lazily additive.
- **Effort:** M. **Depends on:** WS3, WS4.

### WS6 — Windows consent path + iOS native verification checklist (§1, §2, §7)

- **Scope:** Windows: capability probe returns PQ-unavailable ⇒ all establishments take the consent-gated classical-fallback path; blocking consent dialog (exact disclosure text, default = do not send); session flagged `nonPQ` + logged; persistent UI badge; **no PQ strings anywhere on Windows build** (grep gate extended to `windows/`); Windows never offers suite `chhaya-pqxdh-v1`. iOS: verification checklist only — build via `.github/workflows/ios-build.yml` (device + simulator), AWS-LC XCFramework link check, KAT run, crash/lifecycle pass; **runtime behaviour is explicitly unverified**; no iOS PQ claim; iOS keeps capability probe = PQ unavailable until a verified on-device run is recorded and reviewed.
- **Affected files:** capability probe (new or existing capabilities service — discover during implementation), Windows/iOS platform channel glue (`packages/chhaya_pqc` — **read-only**; no new Windows plugin in this work), `ios/` build config (CI only), `test/integration/windows_sqlcipher_test.dart` (adjacent, untouched). iOS verification checklist lives in the PR description + §8 ledger by default — **not** as a new repo file, unless lead approves one.
- **Acceptance criteria:** Windows: consent dialog blocks send until accepted; declining leaves message unsent; session row flagged `nonPQ`; suite never offered (unit test on probe + negotiation). iOS: CI build artifacts produced; KAT log attached to ledger; runtime = marked UNVERIFIED. No `chhaya_pqc` Windows build attempted.
- **Rollback / isolation:** Windows consent gate is unconditional code, not flag-gated (consent is the safety mechanism). iOS probe defaults to PQ-unavailable.
- **Effort:** M. **Depends on:** WS2 (consent dialog wiring), WS5 (badge UI).

### 5.1 Workstream dependency graph and slices

`WS1 → WS2 → WS3 → {WS4 → WS5} ; WS6 after WS2/WS5`. Slices: 6 defined (WS1…WS6). Suggested delivery order: WS1, WS2, WS3, WS4, WS5, WS6. WS1 and WS6-Windows consent UI may proceed in parallel once WS2 negotiation exists.

---

## 6. Acceptance criteria — the 14 section-D criteria (source-verified) + static check

**Provenance note (OQ-1): resolved, source-verified against researcher BEGIN_SPEC_INPUT.** The acceptance criteria below are exactly the researcher's section D list (14 criteria), source-verified and unchanged in wording; each criterion is written concretely and cites the file path already designated in this section (all paths unchanged). Backend commands: `cd backend/server && npm test`. Flutter: `flutter test`. All tests are hermetic unless marked `live` (env-gated backend, see `test/integration/live_messaging_flow_test.dart` pattern).

**The 14 criteria (researcher section D, source-verified) — concrete, numbered, each citing a path already designated in this section:**

1. **`test/unit/database/restore_resume_test.dart` (**rewritten**)** — `restore_resume_test` rewritten, not deleted: pinned test replaced by — two sessions from one restore have distinct SK/chains (byte-inequality test); early post-restore message keys differ from pre-restore (regression vs pinned defect); counter reuse impossible across generations.
2. **`test/integration/resync_restore_test.dart` (new)** — Integration test: backup→restore→send→receive on two in-memory FFI DBs through loopback backend: message decryptable, both sides `session_generation` incremented, resync-ack received, pending message re-sent with new id, server has exactly one copy.
3. **`test/integration/resync_restore_test.dart` (new, same suite)** — Offline-peer test: resync envelope queued server-side, delivered on peer connect, both converge to one session; duplicate resync idempotent.
4. **`test/integration/resync_simultaneous_restore_test.dart` (new)** — Simultaneous-restore tie-break test: both sides derive identical single session (higher generation wins).
5. **`test/unit/crypto/pqc/pqxdh_downgrade_test.dart` (new)** — Downgrade tests: strip PQ prekey sig → bundle rejected; force classical without consent → StateError; retry-with-lower-version forbidden (assert no second attempt); version/suite/offer mismatch → decrypt failure → abort; T tampering flips SK (property test over ≥1000 mutated transcripts).
6. **`test/unit/crypto/ratchet/replay_skip_limit_test.dart` (**extended**)** — Replay tests: replayed initial message → duplicate-rejected, session unchanged; cross-conversation replay → AD failure; replayed resync → idempotent no-op.
7. **`test/unit/database/session_generation_test.dart` (new)** — Rollback test: DB rolled back with keystore counter advanced → client refuses state, forces resync; vice-versa.
8. **`test/unit/crypto/ratchet/spqr_step_reseed_test.dart` (new)** — Delayed-reseed test: after 25 sends, SPQR seed changed, old-epoch keys underivable (old seed wiped / hash-step irreversible), decrypt across the boundary OK within skip window; gap>1000 ⇒ TooManySkippedException with state intact (already-passing harness).
9. **`test/unit/messaging/v2_migration_test.dart` (new)** — Group test: one member restores; per-member resync; no other member forced to restart; contentKey path unchanged.
10. **`test/unit/crypto/pqc/pqxdh_negotiation_test.dart` (new)** — Legacy interop test: v1↔v2 conversation continues classical both directions; no v2 message sent before peer supports it; UI capability flag asserted.
11. **`test/unit/messaging/v2_migration_test.dart` (new, same suite)** — Migration/restore-under-migration test; backup v2 round-trip carries `session_generation`.
12. **`test/unit/crypto/pqc/classical_consent_test.dart` (new)** — Windows: classical-only session completes only with consent flag; without ⇒ hard failure (no silent skip); Windows build must not reference chhaya_pqc (plugin absent).
13. **`test/unit/crypto/pqc/pqxdh_aead_failure_test.dart` (new)** — Fuzz: header/envelope parsers (existing fuzz harness extends); no new crashes/hangs; AEAD failure ≠ state advancement (already pinned — keep).
14. **`scripts/check_transcript_binding.py` (static check, required — implements this criterion; see below)** — No Pqxdh/DualKem code path may compile-link into production messaging without the §B2 transcript binding (static check / import-linter).

**Static check (required — implements criterion 14):** `scripts/check_transcript_binding.py` — scans `lib/` for every HKDF call in the PQXDH/v2 path and fails unless each SK derivation passes `salt=SHA256(T)` and an `info` starting with `"Chhaya-PQXDH-v1"` (or `"Chhaya-Classical-Fallback-v1"` for the consent path), and `T` construction appears in exactly one canonical builder. Exits non-zero otherwise; wired into CI (`.github/workflows/ci.yml`) by lead as part of WS5. This is the **"no PQXDH without transcript binding"** gate. (Recommended, non-required: `scripts/check_no_pq_claims.py` grep gate for WS6 surfaces.)

**Counts:** 14 criteria (researcher section D, source-verified) — items 1–13 are test files (item 1 rewritten pin; item 6 extended existing; items 2, 3, 4 integration; items 1, 5, 6, 7, 8, 9, 10, 11, 12, 13 Flutter unit) — item 14 is the static transcript-binding gate (`scripts/check_transcript_binding.py`, wired into CI by WS5). `flutter test` must stay green on every commit; total pass counts are recorded in the §8 ledger. Reconstructed-only rows retired by this source-verified rewrite: the former golden-SK/T-vector row (`test/unit/crypto/pqc/pqxdh_establishment_test.dart`), and the §4.6 prekey obligations rows (`backend/server/test/prekeys-bundle.test.cjs` and `backend/server/test/prekeys.test.cjs`) have no counterpart in section D and are removed from this list; the backend prekey test obligations they carried remain normative in §4.6 (unchanged), and §4.6 / WS1 acceptance do not reference them. Backend `npm test` coverage of §4.6 is independent of this section.

---

## 7. Non-goals and external gates

### 7.1 Non-goals (explicit, binding)

1. **Multi-device** (Sesame, per-device sessions, cross-device restore-to-same-account, revocation propagation) — out of scope; must not be implied by resync/restore UI, docs, or claims.
2. **True SPQR** — blocked on libcrux incremental-KEM FFI + external review (§3.9). Not implemented, not claimed, not named as present.
3. **Dual-KEM / NTRU** (algorithm diversity) — placeholder scope unchanged; no dual-KEM handshake in this work.
4. **No PQ on Windows** (no `chhaya_pqc` Windows plugin; build not attempted) and **no PQ claims for Windows** — consent-gated classical only.
5. **No iOS runtime claims** — iOS is build-verified + KAT-verified at most; runtime unverified until a reviewed on-device run exists.
6. **Android PQ = arm64 only** — x86/ARM32 not covered; upstream AWS-LC CI covers arm64; other ABIs report PQ-unavailable.
7. **Group membership authentication** — stays trusted-server; resync does not authenticate membership and must not be presented as doing so.
8. **No "post-quantum secure messaging", no "secure restore", no default-on, no FIPS-validation claim, no SPQR claim, no interim marketing** — until the §7.2 gate passes (§1.2).
9. **No silent classical fallback** anywhere; consent + logging + flag always.
10. **No server-side private material, no server-side session crypto, no admin access to keys.**
11. **No availability/production claims for the free Render testing service** — sleeping and database-expiry limits make it unusable as production infrastructure; prekey tables can silently vanish with a free-tier Postgres; no production language references Render.
12. **No change to onion/mesh/sealed-sender/local-only/SFrame scope** — all remain their own tracks.
13. **No crypto agility beyond the registered suites** — no negotiated algorithms outside the suite registry; no downgrade-friendly extension points.
14. **No changes to `docs/feature-verification-127.csv` / `docs/delivery-checklist.md` statuses** in this work.

### 7.2 External gate (hard)

**Independent external cryptographic review is required before** (a) default-on of `chhaya_pq_hybrid_v1`, (b) any "post-quantum" or "secure restore" user-facing claim, (c) marking CSV rows 21/23/24 or checklist rows "PQ hybrid/session bootstrap"/"PQ ratchet"/"Encrypted backup" as done.

**Review scope (must all be covered):**

1. Protocol composition (PQXDH as instantiated here, deviations §3.1, `SK` equation and salt binding).
2. Negotiation/downgrade state machine (§3.5, §3.6 — incl. multi-flight tampering and echo verification).
3. Resync extension (§3.7 — `chhaya-resync-v1`, tie-break, ack semantics, store-and-forward interaction).
4. Transcript encoding (§3.3 byte-level canonical form and its domain separation).
5. Restore interaction (§2.1, §3.8 — `restore_generation`, dual-store, rollback detection, pending-message re-creation).
6. Implementation review of the v2 path and its tests (criteria 1–14).

**Gate evidence:** written external report + remediation of findings + lead sign-off recorded in `docs/delivery-checklist.md` (External audit row) by the lead — **not** by this spec's implementation. Until then: feature flag default-off, no claims, status `NOT RELEASE VERIFIED`.

### 7.3 Did-not-run / cannot-verify capabilities (must stay visible)

| Capability | State in this work |
|---|---|
| Windows PQ | **Does not exist.** Consent-gated classical only. No build attempted. |
| iOS PQ runtime | **Unverified.** Build + KAT only, if WS6 completes. |
| Android x86/ARM32 PQ | **Unavailable** (arm64-only decision). |
| True SPQR | **Blocked** (libcrux FFI + review). |
| Dual-KEM | **Placeholder**, untouched. |
| External review | **Not commissioned** at spec time. |
| Render free-tier PQ availability | **Not guaranteed.** Prekeys expire with the free DB. |
| Multi-device resync | **Out of scope.** |
| Secure restore claim | **Forbidden** until gate. |
| Post-quantum secure messaging claim | **Forbidden** until gate. |

Render free-tier implications (normative for operators): prekey consumption is destructive (atomic pop); a slept/expired Render Postgres can silently zero the prekey tables; clients must handle `404/409/empty` by aborting establishment with a clear error (not falling back silently), and self-hosters must provision persistent Postgres + a runbook for prekey re-upload. No SLA, no production claim; echoes `docs/threat-model.md` "Required production gates".

---

## 8. Verification ledger template (developer MUST fill, do not fabricate)

Copy this table into the PR description or a release-note file. Every row needs a real command + real pass/fail counts + date + initials. **Blank or invented rows = blocked merge.** Rows marked UNVERIFIED stay unverified; they are not failures, they are honest gaps.

| # | Item | Command / evidence | Expected | Actual (pass/fail counts) | Date | Verifier | Status |
|---|---|---|---|---|---|---|---|
| L1 | Flutter analyze | `flutter analyze` | 0 errors | | | | |
| L2 | Flutter unit/integration | `flutter test` | all green (record count) | | | | |
| L3 | Static transcript gate | `python scripts/check_transcript_binding.py` | exit 0 | | | | |
| L4 | Backend lint+test | `cd backend/server && npm run lint && npm test` | green (record counts) | | | | |
| L5 | CI (all jobs) | `.github/workflows/ci.yml` run URL | green | | | | |
| L6 | Android arm64 build + install | `.github/workflows/android-build.yml` artifact + Pixel 8a | arm64 APK; v2 path flag-off default | | | | |
| L7 | Android arm64 PQ round-trip (device) | WS6-style harness on device | ML-KEM encaps/decaps OK | | | | |
| L8 | iOS build (device+sim) | `.github/workflows/ios-build.yml` | builds + links; artifacts attached | | | | |
| L9 | iOS runtime behaviour | on-device run | **UNVERIFIED** (no claim) | | | | UNVERIFIED |
| L10 | Windows consent flow | WS6 manual + unit test | consent required; `nonPQ` flag; no PQ strings in Windows build | | | | |
| L11 | Windows PQ | — | **DOES NOT EXIST** | n/a | n/a | n/a | UNVERIFIED |
| L12 | Concurrent prekey pop (load) | §4.6 prekey obligations on CI Postgres | distinct pops, invariants hold | | | | |
| L13 | Restore→resync two-phone | manual or `live` gated test | resync invisible; old session dropped; ack received | | | | |
| L14 | Rollback drill (flag off) | toggle `chhaya_pq_hybrid_v1=false`, legacy path | legacy still receives; no crashes | | | | |
| L15 | External cryptographic review | reviewer report | scope §7.2 all items | not commissioned | | | UNVERIFIED |
| L16 | Claims audit | grep `lib/ windows/ android/ ios/ web/` for forbidden strings (§1.2) | zero hits | | | | |
| L17 | Legacy blob wipe after 50 v2/30d | criterion 14 | wipe invoked | | | | |
| L18 | Data preservation post-restore | criterion 8 + manual spot-check | identity keys/messages/backups intact | | | | |

Unverified rows ledger (must list explicitly): L9, L11, L15, plus anything skipped/faked. "Did not run" must be written, never implied.

---

## 9. Rollback plan and data-preservation notes

### 9.1 Golden rules (never violated, including rollback)

**Never delete, rewrite, or reset:** identity private keys (SQLCipher `users` + keystore-wrapped blobs), recovery phrases, contacts, conversations, **messages**, **backups** (export files + phrase-derived key material), outbox content. The only cryptographic state this work may delete is: (a) superseded ratchet/session blobs (post-resync drop, §3.7), (b) legacy session blobs past the 50-msg/30d window (§3.11), (c) consumed one-time prekeys (server-side pop, by design), (d) SK/chain material on session wipe.

### 9.2 Flag-based rollback (primary path)

1. Server: `PREKEYS_ENABLED=false` ⇒ prekey endpoints return 503; clients fail-closed (abort establishment, no silent downgrade). Postgres prekey tables remain (inert; §9.4).
2. Client: `chhaya_pq_hybrid_v1=false` (default anyway) ⇒ no v2 offers/establishment; persisted legacy sessions receive-only; persisted v2 sessions remain decryptable (v2 code stays compiled).
3. UI: WS5 badge hides; claims grep gate still passes (no PQ strings by construction on flagged-off builds).
4. Verify per §8 rows L10, L14, L16.

### 9.3 Binary rollback (emergency only)

Rolling the store binary back to **14.0.1** orphans every v2-established conversation (14.0.1 has no v2). **Unsupported.** Supported emergency path = hotfix release with flag off + (if server was enabled) prekey endpoints 503. Communicate honestly; do not claim uninterrupted PQ messaging.

### 9.4 Migration / data notes

- Local DB schema bump adds **nullable** columns/kv keys only (`restore_generation`, `session_generation`). Forward-only. **No down-migration in this work** (checksummed migration history in `db.ts` makes silent down-edits a hard error — good). Remote Postgres migration (WS1) is additive-only; **never `DROP TABLE prekey_*`** in rollback; disable endpoints instead.
- `replaceAccountSnapshot` continues to clear ratchet/session kv rows and outbox on restore (existing, intentional). This spec **does not expand** that deletion scope; it adds `restore_generation` recording + resync on top. Do not add message/contact/conversation deletion.
- Backup/restore drill (`python scripts/database_ops.py restore-drill`) remains the server-side reference; client restore path is covered by criteria 7, 8.
- Stuck pending messages: re-created with new messageIds from **DB content** (never from stale envelopes), only after resync ack; original rows are marked superseded (retained for 30 days for forensics, then expired by the disappearing-content machinery — no new tombstones in this work).
- Server restart mid-pop: transaction atomicity (§4.3) guarantees no half-popped OPK; a popped-but-undelivered OPK is lost (peer establishment fails; retry with fresh fetch — acceptable; last-resort covers pathological loss).
- Identity keys and messages are never inputs to any prekey/restore/resync code path except as read-only context; no code may write them.

### 9.5 Abort conditions for the developer (ask lead, do not improvise)

- OQ-1/OQ-2 (resolved 2026-11-08, source-verified against researcher BEGIN_SPEC_INPUT) regressed, contradicted, or unpinned when WS2 starts ⇒ stop.
- Any test requiring fixture private keys from outside the repo test harness ⇒ stop.
- Any request to name/claim SPQR, mark a gate item done, or touch CSV/checklist statuses ⇒ refuse; quote §1.2/§7.
- Evidence that the existing v1 classical path regresses ⇒ stop, rollback WS2/WS3 merges, page lead.

---

## Auto-Forecast

- `estimated_scope`: **large** (>400 lines; multi-file, crypto + backend + DB + UI)
- `affected_files`: `backend/server/src/{db.ts,routes.ts}`, `backend/server/test/*.cjs` (new), `lib/core/crypto/{pqc/pqxdh.dart,pqc/hybrid_kex.dart,ratchet/{spqr.dart,session_state.dart,session_store.dart}}`, `lib/core/database/local_database.dart`, `lib/services/messaging/{ratchet_message_codec.dart,messaging_service.dart}`, settings/conversation UI, `test/unit/**`, `test/integration/**`, `scripts/check_transcript_binding.py`, `.github/workflows/ci.yml` (lead edit)
- `suggested_phases`: WS1 → WS2 → WS3 → (WS4) → (WS5) → WS6, six bounded phases as defined in §5; do not delegate as a single task.

## Task Contract

- **objective:** Implement hybrid PQ session establishment (PQXDH rev 3 with documented deviations, Android arm64 PQ-capable) and post-restore re-establishment (resync) per this spec, behind a default-off feature flag, with backend prekey infrastructure, the 14 tests + static transcript gate, and honest claims — no post-quantum/secure-restore claims, no default-on, pending independent external review.
- **success_criteria:** criteria 1–14 green; `flutter test` and backend `npm test` green; `python scripts/check_transcript_binding.py` exits 0; flag-off build behaves exactly as 14.0.1 for legacy sessions; Windows classical-consent path enforced; zero forbidden claim strings; ledger (§8) filled with real commands/counts; external-review gate recorded as blocking merge-to-default-on.
- **non_goals:** multi-device; true SPQR; dual-KEM/NTRU; PQ on Windows/x86; iOS runtime verification; group membership auth; Render production availability; CSV/checklist status flips; FIPS validation; onion/mesh/sealed-sender scope.
- **assumptions:** AWS-LC pin unchanged (`v5.11.0`, commit fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6); `chhaya_pqc` stays Android arm64 + iOS only; `authMiddleware`/`rate-limit` patterns reused as-is; local SQLCipher schema additive bump acceptable; initiator role = smaller `'05'`-hex chhayaId retained; repo conventions (LP encodings, `'chhaya-*-v1'` info strings, hex keys) followed; external review will not bless skipping the T-tests.
- **open_questions:** **OQ-1** — RESOLVED 2026-11-08, source-verified against researcher BEGIN_SPEC_INPUT; the literal section-D list is now the §6 acceptance list (14 numbered criteria); reconstructed-only rows (former golden-SK and prekey rows) retired, backend prekey obligations remain normative in §4.6. **OQ-2** — RESOLVED 2026-11-08, source-verified against researcher BEGIN_SPEC_INPUT; exact `ikm` layout pinned in §3.1.4/§3.4 (`0xFF*32 ‖ DH1‖DH2‖DH3[‖DH4]‖SS`, salt = SHA-256(Transcript), info = `"Chhaya-PQXDH-v1"‖suite_string`). **OQ-3** — `session_generation` storage site (kv key vs `conversations` column) — WS3 picks one, records here. **OQ-4** — consent dialog exact disclosure text + cadence (every Windows session vs once per conversation) — product/design decision, blocks WS6 UI polish, not code structure. **OQ-5** — prekey tables' retention/runbook on Render free-tier wipe — operator doc location.
- **accepted_tradeoffs:** re-sent pending messages may duplicate at peer (new ids, accepted); server sees prekey fetch metadata; best-effort memory wiping; last-resort PQSPK weaker than OPK by design; legacy sessions receive-only until 50 msgs/30d; free-tier Render unsupported for production; resync is novel unreviewed crypto (gate applies); deleting `ratchet_message_codec._state` removes any deterministic establishment (intentional).
- **validation:** `flutter analyze`; `flutter test`; `cd backend/server && npm run lint && npm test`; `python scripts/check_transcript_binding.py`; CI run for `.github/workflows/ci.yml` + `android-build.yml` + `ios-build.yml`; Pixel 8a device run (ledger L6/L7); two-phone resync drill (L13); claims grep (L16).
- **ask_abort_triggers:** OQ-1/OQ-2 (resolved 2026-11-08, source-verified) regressed or contradicted at/after WS2 start; any request to enable the flag by default, add forbidden claims, mark CSV/checklist done, or ship SPQR naming; any weakening of AEAD-failure hard-abort; missing Android arm64 evidence for ML-KEM; reviewer findings unremediated; data-preservation violation in migration/rollback; need for a new dependency not pinned by repo policy.

## Handoff packet (for lead → developer)

- Objective: as Task Contract. Current state after this spec: **no code written**; `docs/spec-pq-hybrid-resync-v1.md` created (only file touched).
- Decisions made (this spec): SD-1 Ed25519-over-LP (§3.2) prekey signature encoding; SD-2 7-day PQSPK window / 30-day SPK window / 7-day rotation grace / 30-day OPK purge; SD-3 byte-level LP transcript; SD-4 AEAD AD = `header‖T`; SD-5 dual rate-limit keys (IP-HMAC + per-target-user); SD-6 rewrite `pqxdh.dart` in place.
- Files read: `docs/{threat-model.md, delivery-checklist.md, feature-verification-127.csv, pqc-provider-proposal.md, crypto.md, feature-register.md}`, `lib/core/crypto/{pqc/*, ratchet/spqr.dart, ratchet/double_ratchet.dart, ratchet/session_store.dart}`, `lib/services/messaging/ratchet_message_codec.dart`, `lib/services/messaging/messaging_service.dart`, `lib/core/database/local_database.dart`, `test/unit/database/restore_resume_test.dart`, `backend/server/src/{db.ts, routes.ts, rate-limit.ts, migrations.ts}`, `.github/workflows/ci.yml`, `packages/chhaya_pqc` (listing), `pubspec.yaml`, `backend/server/package.json`.
- Validation state: none run (spec-only change; repo untouched except this file).
- Blockers: none from OQ-1/OQ-2 (both resolved 2026-11-08, source-verified against researcher BEGIN_SPEC_INPUT); external review not commissioned (expected).
- Next action: dispatch developer for WS1 (OQ-1/OQ-2 resolved, source-verified); WS6 consent UI in parallel once WS2 lands. Lead records external-review gate state before any default-on change.

## Result Contract

- **status:** `pass` (spec written; implementation intentionally not started) — with `needs_changes` on content: OQ-1/OQ-2 now read **resolved, source-verified against researcher BEGIN_SPEC_INPUT** (2026-11-08); the external review gate is unchanged and still blocks default-on and any post-quantum/secure-restore claim.
- **summary:** `docs/spec-pq-hybrid-resync-v1.md` created; 9 required sections + Auto-Forecast/Task/Result contracts; OQ-1 resolved (source-verified): the §6 acceptance list now contains exactly the researcher's section-D 14 criteria, numbered, with the §6-designated file paths (unchanged); reconstructed-only rows retired (former golden-SK and prekey rows; backend prekey obligations remain normative in §4.6). OQ-2 resolved (source-verified): exact SK equation pinned in §3.1.4/§3.4 (`ikm = 0xFF*32 ‖ DH1‖DH2‖DH3[‖DH4]‖SS`, salt = SHA-256(Transcript), info = `"Chhaya-PQXDH-v1"‖suite_string`); ambiguous `F‖DHs` wording corrected everywhere in §3. Backend/client/migration/claims/rollback boundaries fixed from BEGIN_SPEC_INPUT verbatim.
- **artifacts:** `docs/spec-pq-hybrid-resync-v1.md` (this file). No other files modified or created. No CSV/checklist statuses flipped.
- **next_recommended:** lead → developer for WS1 (OQ-1/OQ-2 resolved, source-verified); the external-review gate stays blocking for default-on and claims; then developer for remaining workstreams per §5.1.
- **risks:** §1.2 claims discipline depends on enforcement (grep gate); resync remains unreviewed novel crypto until the gate (expected, flagged everywhere); free-tier Render prekey loss; external review not commissioned (expected) — and pre-existing references to the retired T-labels (e.g. §5 WS2–WS5 acceptance lines, §7.2 gate scope, Task Contract `success_criteria`, §8 ledger L12) are now stale and need a lead fix-up pass (not edited here; out of this change's scope).
- **skill_resolution:** no `Skill Resolution` block in handoff ⇒ fell back to global `<available_skills>`. Used as checklists: `security-and-hardening` (boundary validation, rate limits, no secrets, parameterized SQL, no private material at server boundary — reflected in §4.2–4.6) and `test-driven-development` (RED-first T-tests, real-implementation preference, no test deletion — reflected in §6 and WS3 test rewrites). Skipped: `api-and-interface-design` (endpoints specified directly in §4.2), `documentation-and-adrs` (spec is the decision record; an ADR for PQ activation is required post-gate by lead), `oak-enrich-task` (input was already an enriched spec input), `browser`. Fallback if any skill should apply later: lead re-invokes with an explicit Skill Resolution block.

## Markers

- `implementation_decisions_count`: 6 (SD-1…SD-6) + normative protocol selections in §3 (suite registry, LP encoding, AD composition, tie-break memcmp, dual-store write order, legacy-drop threshold — each flagged review-pending where applicable)
- `testing_decisions_count`: 14 (researcher section-D criteria, source-verified — former T-label mapping retired; see §6 counts note) + 1 static gate + backend prekey obligations (§4.6)
- `slices_defined`: 6 (WS1…WS6)

## Appendix — contradictions and tensions found vs source docs

1. **`docs/crypto.md` / `spqr.dart` vs this spec:** source comments describe `SpqrChain` as "SPQR" / "Sparse Post-Quantum Ratchet (V14 Part 4)". This spec forbids SPQR naming for the v1 design. Resolution: rename *claims*, not the file; code comments updated in WS4; `SpqrChain.reseed` mechanism is reused as-is (it is a mechanism, not a claim).
2. **`restore_resume_test.dart` header** pins deterministic restart as *known dangerous behaviour*; this spec makes its deletion normative (§3.11, criterion 8). The file's stated expectations are inverted by design.
3. **`ratchet_message_codec.dart` `_state`** (deterministic `deriveSharedSecret` from static identity) directly contradicts zero-key/nonce-reuse — deleted in WS3 per research input.
4. **`docs/delivery-checklist.md` "PQ ratchet"** ("Deterministic epoch chain only / Real PQ reseeding…") — this spec delivers hash-step + sparse reseed, still **not** "real SPQR"; checklist row must stay unclaimed (§1.4).
5. **`docs/pqc-provider-proposal.md` gate 5** ("protocol activation gated until the authenticated key-distribution and migration design has independent review") — this spec is that design; the gate remains **not passed**. Consistent, but this spec must not be read as satisfying the review itself.
6. **`docs/threat-model.md`** says "active ratchet state is not yet included in backup" — unchanged; §2.1 adds restore/rollback resync which *reduces* but does not eliminate this gap (backup still lacks ratchet state).
7. **`docs/feature-verification-127.csv` row 1** still cites "Triple Ratchet PQ contribution … absent" — remains true until the gate; no status flip authorized here.
8. **`pubspec.yaml` / `packages/chhaya_pqc`** confirms Windows plugin absence — §2/§7 Windows claims boundary is grounded in repo reality, not preference.
9. **`backend/server/src/db.ts` checksummed migrations** make any edit to existing migration statements a hard startup failure — hence §4.1 append-only rule and §9.4 no-down-migration.
10. **Research input internal tension:** "v1 = one-way hash-step chain … sparse reseed ~25 sends/7d" vs the `SpqrChain.advanceEvery=10` epoch cadence — resolved by §3.9 (reseed cadence independent of epoch advance) and the no-SPQR-naming rule.
