# Chhaya Apple-inspired motion and type

Design read: a privacy-focused mobile messenger for people who value a calm,
distinctive interface. Native navigation and familiar controls carry the
interaction; warm cream/coral, Departure Mono, and measured motion give Chhaya
its own character.

The Apple Design Skill is used for the iOS conventions, platform typography,
motion and accessibility review. Taste Skill is aimed at web landing pages, so
only its transferable checks for visual restraint, purposeful animation, and a
recognizable product identity apply here. The implementation remains Flutter
and uses Flutter's built-in platform behavior.

## Typography

| Role | iOS and macOS | Android | Use |
|---|---|---|---|
| Normal interface text | SF Pro system text/display proxies | Inter | Messages, controls, labels, settings and reading |
| Brand display | Departure Mono 1.500 | Departure Mono 1.500 | Chhaya headings, identity details and pixel accents |
| Recovery words | Roboto Mono | Roboto Mono | Recovery phrase alignment |

Claude's restrained editorial voice and comfortable reading rhythm inform the
copy and hierarchy. This does not bundle or claim ownership of an Anthropic
typeface. Departure Mono is unchanged.

## Interaction map

| Interaction | Current behavior | Accessibility and limits |
|---|---|---|
| App opening | Home and onboarding enter with a short fade and scale; the route retains platform navigation behavior. | Custom entrance is removed when reduced motion or accessible navigation is enabled. |
| Chat opening | The conversation avatar uses a shared Hero tag between the chat list and chat header; iOS keeps the interactive back gesture. | The Hero is disabled with reduced motion; navigation remains available. |
| Message sending | Newly inserted messages enter once with a small fade, rise and settle. | Existing messages do not replay the entrance on every refresh. |
| Long press | The message lifts into a contextual action menu with haptic feedback. | Reply is also exposed as a semantic action; reduced motion uses a static action sheet. |
| Swipe to reply | The bubble tracks a deliberate horizontal drag, adds elastic resistance, and springs back; crossing the reply threshold gives haptic feedback. | A semantic Reply action and long-press menu provide alternatives. |
| Navigation | One shared coral selection marker moves between standard labeled destinations; wide layouts use a NavigationRail. | Flutter retains tab semantics, labels and selected state. |
| Voice recording | The waveform samples microphone levels and updates during user-started recording; the record/stop control changes with the session. | The recording is bounded to 60 seconds and the reduced-motion waveform shows a static level. |
| Image preview | The inline image shares a Hero transition with a zoomable full-screen viewer. | Close and export controls remain available; reduced motion disables Hero transitions. |
| Bottom sheets | Reusable sheets have a short present/dismiss transition, dim the background, constrain their width and allow standard drag settling. | Dismissible sheets have a grab handle; the recorder is intentionally non-dismissible while recording and has explicit Cancel/Use recording actions. |
| Search | Focus expands the field horizontally while the keyboard opens; list content follows Flutter's normal keyboard resize. | Clear-search has an accessible label. The focus transition is brief and becomes immediate under reduced motion. |
| Theme change | Semantic colors interpolate across a 300 ms theme transition. | Reduced motion makes the change immediate; both light and dark palettes are retained. |
| App lock | Successful device authentication or PIN advances into the home route's opening transition. | This is the existing app lock flow. Chhaya has no separate secure-vault screen, so the UI does not imply that one exists. |

## Motion policy

Motion intensity stays moderate: transitions clarify continuity or confirm an
action, and no decorative loop runs in the background. `ChhayaMotion.reduced`
respects both the platform's animation preference and accessible-navigation
setting. Animation stays supplementary to labels, state, and direct actions.

The animation behavior is implemented in Flutter, not as an Apple-native
SwiftUI animation. Timing and feel vary by OS version and device. Automated
widget renders and existing UI interaction checks cover Flutter behavior;
physical-device haptics, voice recording, keyboard timing, screen readers, and
performance still need Android and iPhone validation.

## Design references

- [Apple Design Skill](https://github.com/dickwu/apple-design-skill), applied with its iOS, motion, typography, sheets, search, gestures, and accessibility guidance.
- [Taste Skill](https://github.com/Leonxlnx/taste-skill), applied only where its web-oriented guidance transfers to a native product UI.
- Flutter's [system font family proxies](https://api.flutter.dev/flutter/painting/TextStyle/fontFamily.html) map `CupertinoSystemText` and `CupertinoSystemDisplay` to SF Pro on Apple platforms.
