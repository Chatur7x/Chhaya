# Recovery and support — Version 15 preparation

Scope: backup and restore of a Chhaya account on this development build line, and where to get help. This is an internal support runbook for a development build, not a service-level commitment. No production support channel exists.

Repo: `https://github.com/Chatur7x/Chhaya` · Issue tracker (support contact): `https://github.com/Chatur7x/Chhaya/issues`

## Back up now (before anything risky)

In the app:

1. **Settings → Encrypted Backup** ("Save encrypted backup").
2. Store the exported encrypted backup file somewhere durable — ideally encrypted offline storage or a second machine, not only the device itself.
3. Separately, secure your **recovery phrase** (BIP-39 word list). The phrase is the root of account recovery and is never derivable from the backup alone on a fresh install that fails identity validation; the backup is validated against the phrase.
4. A backup of the local database is SQLCipher-protected; the export additionally wraps it with a phrase-derived key. Treat the export as sensitive anyway: it contains your message history in encrypted form.

Export before: uninstall/reinstall, switching between debug-signed and release-signed builds, OS reinstall, device migration, acceptance/integration tests on the same device, or any restore drill.

**Android note:** automatic backup is disabled by the shipped manifest (`allowBackup=false`). iOS has no supported distribution at all on this build line. There is no cloud backup provided by Chhaya.

## How to restore

1. Install/build the app and open it.
2. On onboarding, choose **"Restore an account" / "Restore with phrase or backup"**.
3. Supply the recovery phrase and (for full history) the encrypted backup file/text.
4. What a successful restore does today (per `docs/delivery-checklist.md`): validates the phrase-derived identity, then replaces profile/contacts/conversations/messages in a SQLCipher transaction; old ratchets and the outbox are cleared rather than cloned; on failure, credentials are compensating-rolled-back.

### Limits — read before relying on a backup

- **A backup does not revive sessions. Sessions re-establish.** Active ratchet state is not included in the backup; restored conversations must re-derive sessions with peers, and that flow is not fully exercised end-to-end. Do not treat a restore as proof of uninterrupted messaging. Known restore defects were pinned in the 2026-11-08 window (e.g., byte-identical initiator session re-derivation / key-nonce reuse hazard; restored unsent messages can remain stuck pending); local mitigations exist behind a default-OFF flag and remain unverified on devices and unreviewed externally.
- **Remote copies survive a panic erase or local deletion.** Anything already delivered to recipients, stored on their devices, in their backups, in screenshots, or on the server (encrypted envelopes) is outside your control after the fact. Disappearing messages are local-expiry behavior, not guaranteed erasure.
- **The free test backend (`https://chhaya-ys50.onrender.com`) expires 2026-11-27.** A backup does not protect you from that service loss; it only protects local data. Deploy your own backend (`docs/self-hosting.md`) or accept the loss.
- Restore is not atomic in every edge ("key/database restore is not fully atomic" — `docs/threat-model.md`), and failure behavior on real devices is not yet established.
- Encrypted backups protect confidentiality under the recovery-derived key; they do not prove multi-device continuity, and linked-device enrollment is not a complete authenticated device-transfer protocol.

## Support contact = the repository issue tracker

Report problems at `https://github.com/Chatur7x/Chhaya/issues`. Include build/artifact identity, platform, OS/device, backend origin, and repro steps. **Never post recovery phrases, identity keys, or backup contents.** For security reports, see `SECURITY.md`.

There is no email/phone/chat support channel, no SLA, no managed incident response, and no operations owner for the test backend.

## Lost verification account — what cannot be recovered

`com.chaaya.app.chaaya.verification` (Pixel 8a) disappeared on 2026-10-29, presumed uninstalled by an integration-test teardown targeting the stale cached APK package. The installed-package manifest disables Android backup; no backup file was located in a workspace/Downloads/Documents/phone search; its Keystore-wrapped identity was destroyed with the app sandbox. Status: **LOST, not compromised.**

- **The lost verification account cannot be recovered, aside from the owner-held recovery phrase.** If the owner holds the phrase, the account can be re-created from it on a fresh install (with no guarantee of recovering previously exchanged history beyond what the phrase plus any backup the owner holds can restore).
- **Support CANNOT retrieve lost identity keys, database keys, ratchet state, or verification accounts.** No maintainer, CI artifact, backend record, or support channel can reconstruct them; the backend stores encrypted envelopes, not recoverable plaintext keys. Do not send anyone a phrase believing they can help restore keys — that will not work and will compromise the account.
- The main account `com.chaaya.app.chaaya` (Android private-space user 11) is believed intact and is to be preserved; it is excluded from any acceptance or reset flow.
- Related references: `docs/ponytail-audit-2026-10-29.md` (incident), `docs/version-15-status.md` §8 and §10, `docs/INSTALL-v15.md` (uninstall/data-retention warning).

## What this document is NOT

Not a guarantee of recovery, not a support contract, not a data-protection certification. Chhaya is a development build with no independent cryptographic or penetration review; treat all recovery assurances here as best-effort and unverified on physical devices.
