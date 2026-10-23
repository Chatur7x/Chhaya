# Chhaya mobile UI review — 23 October 2026

## Scope and direction

The user selected warm cream/coral, calm and minimal. Flutter and the current messaging architecture are preserved. Frontend-design, Impeccable, UI/UX Pro Max Flutter guidance, and design-system instructions were read from local copies because D:/Skills is absent. Web-only landing-page/React patterns were not substituted into the native app.

## Implemented

- Consistent cream canvas, flat surfaces, Inter typography, and licensed bundled Roboto Mono for identity strings.
- Darker action coral and semantic status/error colors with measured normal-text contrast exceeding 4.5:1 on cream and white where used.
- Four-destination navigation, with a rail at wider widths; constrained content measure.
- Clear conversation rows, name/ID search, explicit action labels, and safe local-history deletion confirmation.
- A visible send affordance with empty/sending states; pending-message status; accurate unsupported-feature explanations.
- Onboarding, signup, restoration, verification, contact profiles, voice-call presentation, settings, startup/error recovery, and scrollable unlock controls.
- Real font-license browsing rather than a static list of package names.

## Defects caught and repaired

- The legacy restore form combined obscuring and multiple lines, which Flutter rejects. Both visibility modes are exercised.
- The onboarding header overflowed at 200% text.
- Settings groups painted opaque decorations above ListTile ink effects; groups now use Material surfaces.
- Font names existed without files. Fonts are bundled and icon/ID fonts are explicitly loaded in the review harness.
- Compact conversation rows truncated names too aggressively; large-text layouts give names additional lines and move timestamps.
- Signup previewed a different random identity from the real account identity. The preview step was removed.
- Profile chat actions created local-only conversation IDs and block controls did not persist. Actions now save their state and use the API for missing conversations.
- A missing recovery phrase was replaced with invented words. The UI now reports unavailability.
- The startup screen claimed a tunnel was being secured even though the current transport is HTTPS. It now describes opening the account and offers retry on failure.

## Evidence and limits

Automated review captures 48 cases across 16 surfaces at 360×820dp, 320×568dp with 200% text, and 768×820dp: unlock, loading, startup error, voice call, keyboard-open conversation, adaptive home, chats, contacts, calls, settings, onboarding, signup, restore, conversation, profile, and verification. These are actual Flutter widget renders with fictional fixtures, not image-generated mockups or physical-device screenshots.

The suite checks runtime/layout exceptions, recovery-field visibility, navigation bar/rail adaptation, send controls, contrast, and the existing application regressions. CI exports the PNGs as Chhaya-Design-Review. Native Android and unsigned iOS compilation are checked separately.

Physical Android/iPhone screen-reader, keyboard, system gesture, camera, WebRTC, and performance validation remains necessary. This review does not certify full WCAG compliance or a bug-free product. The user-approved light appearance is the current default; a fully semantic dark redesign is outside this pass.

## Verification evidence

App build commit: `1d9dff8eb3702437400dcdd73dfc4e918f8ab261`.

- [Flutter analysis, 187 passing tests, one native-device test skipped, and backend integration](https://github.com/Chatur7x/Chhaya/actions/runs/39910321097)
- [Android APK build](https://github.com/Chatur7x/Chhaya/actions/runs/39910321118)
- [Unsigned iOS build and macOS checks](https://github.com/Chatur7x/Chhaya/actions/runs/39910321114)

The keyboard-open case supplies a 260dp keyboard inset to the actual Flutter
layout. It does not simulate an operating-system keyboard or prove native IME
behavior. All 48 PNG files were validated before packaging.
