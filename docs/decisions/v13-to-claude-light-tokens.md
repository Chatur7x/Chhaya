# Decision: V13 → Claude Light token mapping (Part 8)

Status: approved (verbatim) by the product owner on the Part 8 execution brief.
Applies to: `lib/ui/screens/**` rewrites only.

Part 8 forbids new functionality. Screens keep their behaviour, layout intent,
and navigation, while their *styling vocabulary* moves from the V13 palette to
the Part 6 Claude Light tokens and the Part 7 widgets.

## Colour tokens

| V13 token | Claude Light (Part 6) | Notes |
| --- | --- | --- |
| `primaryBackground` | `cream` | light default canvas |
| `secondaryBackground` | `surface` | raised canvas |
| `cardSurface` | `surface` / `white` | `white` inside cards on `cream` |
| `inputSurface` | `surface` | inputs sit on `surface` |
| `glassBorder` | `borderSoft` | |
| `separator` | `borderSoft` | |
| `opaqueSeparator` | `borderMed` | stronger separators |
| `fillTertiary` | `hoverCream` | hover / subtle fills |
| `labelPrimary` | `ink` | |
| `labelSecondary` | `inkSoft` | |
| `labelTertiary` | `inkMuted` | |
| `labelQuaternary` | `inkFaint` | hairlines / large graphics only, never small text |
| `online` | `success` | |
| `accent` | `coral` | brand accent |
| `onAccent` | `white` | text/icons on coral |
| `accentGradient` | `coral` | gradients removed → flat |
| `glowGradient` | `coralTint` | gradients removed → flat tint |

## Typography

| V13 | Claude Light (Part 6) |
| --- | --- |
| `'JetBrains Mono'` | `DEPΛ2TɄRE_MONO` (`chhaya_typography.dart`, family `'Departure Mono'`) |
| system sans body | `Inter` |
| system serif display | `Tiempos` |

## Rules that fall out of the mapping

- Gradients are removed entirely; where a gradient was decorative, use flat
  `coral` or `coralTint`.
- Inline styling is replaced by Part 7 widgets (`ChhayaCard`, `ChhayaPrimaryButton`,
  `ChhayaInput`, `ChhayaChatBubble`, `ChhayaAvatar`, `ChhayaAppBar`,
  `ChhayaBottomNav`, `GlassContainer`, `PressableScale`, `NotificationOverlay`).
- WCAG constraints from `chhaya_colors.dart` still bind: `coral` on `cream` is
  restricted (large graphics only); use `coralDeep` for small accent text.
  `warning` on `cream` must always carry an `ink` text label.
- Functional behaviour is frozen: no new state, no new routes, no feature work.
  Navigation stays on `lib/core/router/chhaya_router.dart`.
