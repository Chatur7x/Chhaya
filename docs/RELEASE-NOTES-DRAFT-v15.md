# Release notes DRAFT — Version 15 preparation (this week)

**DRAFT — NOT a release note, NOT a tag, NOT a claim of readiness. Do not publish, quote, or attach to any release. No release tag exists or is implied. Chhaya Version 15 is not released and no gate that matters for a public release passes (see `docs/RELEASE-PREP-v15.md` §4). If published by accident, delete the publication rather than edit the wording.**

Status: draft for owner/lead review. CHANGELOG.md has no Version 15 entry area, and none was added or implied here. No checklist/CSV/ledger status was changed by this file.

Date: 2026-11-14 (preparation week of 2026-11-08 → 2026-11-14). Base range: `b42d4e5` .. `c4b48e6`.

## Version 15 preparation (this week)

Committed work in the preparation window (evidence class per item; none is release verification):

- `56f054d` — Adversarial retry/replay/concurrency/rollback/restore coverage; restore key/nonce hazard and stuck-pending defects pinned, not remediated (unit evidence).
- `5d2faf1` — WS1: prekey bundle backend endpoints (additive); 38 backend tests reported; not deployed; CI not re-run.
- `98aa043` — WS2 (PQ spec): hybrid PQXDH establish/transcript/negotiation helpers + golden vectors (unit evidence; local).
- `1274999` — Version 15 preparation status register recorded; PQ spec (`docs/spec-pq-hybrid-resync-v1.md`) committed.
- `4194a35`, `2d6b9bb` — Fail-closed handling for unreadable lock/settings reads (unit evidence).
- `ed1ff93`, `e022db8`, `4d2e60b`, `fecb2cf`, `88ea78f`, `2eeb9b9`, `1c46316`, `8eeff19` — WS3: v2 establishment/resync restore recovery wired locally behind default-OFF flag `chhaya_pq_hybrid_v1`; audit findings F1–F7 fixed locally (unit evidence; re-review recorded 2026-11-14 as `pass_with_observations`; residuals R1/R2/R3 open).
- `c857be5`, `29dacd2` — Media-transfer spec (proposed; claims gated) and WS3 close-out/re-review recorded.
- `02d2800`, `58beda5` — Resumable media transfer backend (WS-A) added; encrypted transfer work is spec-gated and not client-complete; no release claim.
- `e5fb360` — Fail-closed on corrupt settings reads.
- `eaef7ec`, `3b89eaa` — Ledger rows 26–127 source-based requirements assessment refreshed (`release_verified` unchanged).
- `b42d4e5` — Background reauth lifecycle guard for locked signed-in session (unit evidence). *(Predates the range start; retained for completeness of the "preparation window" narrative.)*
- `c4b48e6` — `fast-xml-parser` bumped past GHSA-474x-hrwr-fgx4.

Environment/state at time of drafting: free Render test backend expires 2026-11-27; verification Android package lost 2026-10-29 (unrecoverable without owner-held recovery phrase; support cannot help); 0/127 ledger rows release-verified; no device, iOS, PQ-external-review or store evidence exists.

**Allowed wording:** "Version 15 preparation is in progress. No release has shipped and none is scheduled; preparation records are kept in `docs/RELEASE-PREP-v15.md` and `docs/version-15-status.md`."

**Forbidden wording:** any "v15", "released", "final", "production ready", "audited", "post-quantum secure", "quantum-safe", or store-availability claim. See `docs/RELEASE-PREP-v15.md` §3 for the full claims policy.
