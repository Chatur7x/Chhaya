# Chhaya — Version 15 preparation builds (DRAFT / internal)

**Development builds only. None of this is a store release, a signed production distribution, or a claim of readiness. See `docs/RELEASE-PREP-v15.md` and `docs/version-15-status.md` for the full gate status — no public-release gate currently passes.**

Distribution is by direct download from CI artifacts and attached files in this repository's history. There is **no** Play Store, **no** App Store, **no** TestFlight, **no** signed IPA, and **no** release download page.

Repository: `https://github.com/Chatur7x/Chhaya`
Issue tracker (how to report problems): `https://github.com/Chatur7x/Chhaya/issues`

## Android — sideloaded APK (NOT a store submission)

Chhaya is not on the Google Play Store. Installation on Android is sideload-only:

- **CI test build (debug-signed):** workflow `Android Build` (`.github/workflows/android-build.yml`) produces `Chhaya-Android-Test-APK` (path inside the artifact: `build/app/outputs/flutter-apk/app-debug.apk`). Download from the run page: `https://github.com/Chatur7x/Chhaya/actions/workflows/android-build.yml` → select the run → Artifacts. It is a debug-signed development build, not production.
- **Local release artifact (private release key):** `dist/Chhaya-14.0.1-arm64.apk` (package `com.chaaya.app.chaaya`, version 14.0.1/code 2). Local artifact only; it is not redistributed by this repository's CI and its custody/backup is unverified.
- Enable "Install unknown apps" for the app opening the APK (browser/file manager) when Android prompts. **Enabling unknown-sources installation carries a real risk: any app with that permission can install arbitrary APKs. Re-disable it after installing, and only sideload from sources you trust.** An APK from outside the store is not vetted by any store review process.
- A different signing certificate from an older installed build can prevent upgrades. Uninstalling to "fix" it deletes local data (see "Uninstall and data retention" below).
- Do not rely on this development build for sensitive communication. PQ is not live; calls are foreground-only; the free test backend expires 2026-11-27.

## iOS — no distribution available

- CI (`.github/workflows/ios-build.yml`) produces an **unsigned** `Runner.app` archive (artifact `Chhaya-iOS-UNSIGNED-Developer-Build`): `https://github.com/Chatur7x/Chhaya/actions/workflows/ios-build.yml` → run → Artifacts.
- The unsigned archive **cannot be installed by downloading and renaming it to `.ipa`**. It requires a Mac with Xcode, Apple code signing, and a registered Apple Developer account to install on a device.
- What Apple membership would enable (none of this is available now): signing and local device installation, TestFlight beta distribution, ad-hoc distribution for registered devices, and eventually App Store submission, subject to review and to all other release gates passing.
- **iOS distribution is NOT available.** No device testing, no signing, no runtime acceptance evidence exists for iOS.
- iOS PQ availability is not claimed (iOS vectors pending; Windows PQ is a stub).

## Windows — CI-produced developer build (development build, not a release)

- Workflow `Windows Build` (`.github/workflows/windows-build.yml`) produces `Chhaya-Windows-Developer-Build` (path: `build/windows/x64/runner/Debug/`). Download pattern: `https://github.com/Chatur7x/Chhaya/actions/workflows/windows-build.yml` → select the run → Artifacts. Artifact retention is limited (14 days); older artifacts expire.
- This is a **debug development build** effective for quick checks only. It is not signed, not packaged for installation, and **the app has never been launched against an account**. Local Windows builds are additionally blocked by a missing ATL dependency (`atlstr.h`).
- There are deliberately no signed-release or installer URLs, because none exist. Any such URL would be fabricated.

## How to report problems

Open an issue at `https://github.com/Chatur7x/Chhaya/issues`. Include:

- Build/artifact you used (workflow + run, or `dist/` file name and checksum), platform and device/OS version, app version, backend origin used (test backend vs self-hosted).
- Steps to reproduce, expected vs actual behavior, screenshots/logs with no private data.
- **Do not include recovery phrases, identity keys, message content, backup files, or any other user's private data.** Redact account IDs if they are not needed for the report.

For security issues, follow `SECURITY.md`: do not publish exploitable issues before maintainers can investigate; report privately per the policy there.

## Uninstall and data retention

- Uninstalling the app **deletes the app sandbox, including SQLCipher database data and Keystore/Keychain-wrapped identity key material**. Android automatic backup is disabled in the shipped manifest, so relying on the OS backup is not a recovery plan.
- **Do not reinstall a package whose data you need without exporting a backup first** (see "Recovery before risky operations" below). This is not hypothetical: the 2026-10-29 incident (`com.chaaya.app.chaaya.verification` on the Pixel 8a) was presumed to have been lost to an integration-test teardown that uninstalled the captured package; no backup was found on the workspace/phone search, and the identity data is presumed destroyed. The main account lives on only because it sat in a separate private-space user. See `docs/ponytail-audit-2026-10-29.md` (incident summary) and `docs/version-15-status.md` §8.
- Reinstalling an update-signed build over the same package normally preserves data; switching signing certificates does not.
- "Delete account" (if offered in the UI) and panic-PIN removal are local operations and do not erase messages held by recipients, remote copies, or backups you have made.

## Recovery before risky operations

Before uninstalling, switching signing builds, enrolling/reseating devices, migrating to/from a new phone, OS reinstall, or any restore experiment:

1. Open **Settings → Encrypted Backup** ("Save encrypted backup") and store the exported encrypted backup file somewhere durable and offline if possible. The file is encrypted under a phrase-derived key.
2. Write down / secure your **recovery phrase** (BIP-39) separately. The phrase is the root of account recovery. The exported backup restores profile/contacts/conversations/messages; active ratchet sessions are not carried over (see `docs/recovery-and-support.md`).
3. Keep the signing keystore (`~/.chhaya/signing/`) and `android/key.properties` backed up in encrypted offline storage if you build releases locally — losing the release key prevents signing compatible updates.

## Known limits of these builds

- Development/testing only; no production availability (free test backend sleeps; database expires **2026-11-27**); foreground-only calls; 256 KB attachment cap; no large/resumable transfers; no background push; no verified PQ messaging; no independent cryptographic or mobile penetration review; 0/127 ledger rows release-verified; no release gates pass except the LOCAL-ONLY engineering gate. See `docs/RELEASE-PREP-v15.md` §4.
