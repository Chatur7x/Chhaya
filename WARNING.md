# ⚠️ SECURITY WARNING

## Affected versions

v1.0.0 through V1.1 (all tags in that range).

## What's wrong

Weak randomness: the Fortuna CSPRNG was seeded exclusively from
`DateTime.now().microsecondsSinceEpoch` — predictable entropy for
ephemeral keys, shared-secret derivation, and AES-GCM IVs.
See SECURITY.md ("Historical issues") for the full disclosure.

## Fixed in

Chaaya-V1.0.4 (commit `fd755ba`, 2026-04-25) — seeds from
`Random.secure()` instead of `DateTime`.

## Action required

If you used any affected version:

1. Upgrade immediately to Chaaya-V1.0.4 or later.
2. Rotate all keys, sessions, and recovery phrases. Do not reuse any
   material generated on affected versions.
3. Assume any data transmitted with affected versions is decryptable
   by an attacker who knew the approximate device time.

## Details

- GitHub Security Advisory: (pending — to be filed; draft in A1-FU report)
- SECURITY.md — "Historical issues (V13 entropy disclosure, TASK A1)"

## Contact

security@<YOUR-REAL-DOMAIN> — replace with the confirmed address before publishing.
Report vulnerabilities privately; do not open public issues for them.
