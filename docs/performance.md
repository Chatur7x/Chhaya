# Android performance notes

These are development observations, not release benchmarks. The phone was a
Pixel 8a running Android 17 (API 37). The installed artifacts use the debug
certificate and are not production releases.

## Changes in this pass

- Foreground message synchronization now polls every 15 seconds after a
  successful server sync, backs off to 30 and then 60 seconds after failures,
  and pauses scheduled polling while the app is backgrounded.
- Local-only accounts skip remote sync, outbox retries, call signaling setup,
  and database reloads; they check again every 30 seconds so a later server
  connection is detected.
- Contact and conversation providers retain their existing state when the
  latest poll contains the same visible data, avoiding redundant screen builds.
- A fresh install starts in Claude Light. A saved appearance preference is
  retained.

## APK comparison

| Artifact | Mode | Size | Notes |
| --- | --- | ---: | --- |
| Earlier Chhaya-V14-NEW | Universal debug | 264,183,914 bytes | Includes the Dart debug kernel and debug-only runtime assets. |
| Current Chhaya-V14-NEW | Profile | 101,795,008 bytes | AOT-compiled Flutter profile build; APK includes arm64-v8a, armeabi-v7a, and x86_64 native libraries. |

The profile artifact is about 61% smaller than the earlier debug APK. It is
still debug-signed, not a Play Store release. Release builds remain blocked by
the native AWS-LC CMake configuration and need a separate fix and verification.

## Device check

The profile APK installed successfully on the Pixel 8a and its Android process
started without a Chhaya crash in the captured logs. Android's notification
permission prompt remained in front of the app, so foreground interaction and
frame-time percentiles still need a physical tap-through. A single memory
snapshot is not enough to claim a sustained RAM improvement.

A reliable frame baseline still needs five cold launches and a repeatable
scroll/send interaction in profile mode.

## Reproduce the profile build

From the repository root, build with:

    flutter build apk --profile --target-platform android-arm64 --no-pub

Then inspect active-device frames and memory after accepting or declining the
system permission prompt:

    adb shell dumpsys gfxinfo com.chaaya.app.chaaya framestats
    adb shell dumpsys meminfo com.chaaya.app.chaaya

Record at least five cold starts and a one-minute chat-list/chat scroll before
comparing frame percentiles or memory. Keep profile/release measurements
separate from debug-build measurements.
