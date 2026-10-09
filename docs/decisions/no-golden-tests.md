# Decision: No golden tests

- **Date:** 2026-10-09
- **Status:** Accepted
- **Applies to:** Part 7 (widgets) and Part 8 (screens), and onward

## Context

The Part 7 and Part 8 specs both asked for "a golden test per widget" /
"per screen". Golden tests render a widget to a PNG and compare against a
committed reference image.

## Decision

**Skip golden tests entirely.** Use behaviour and widget assertions only.

## Rationale

Golden tests are pixel-exact and therefore hostage to the rendering
environment: Android, iOS and Windows produce different antialiasing,
font rasterisation and shadow edges for identical widget code. A golden
suite on a three-platform app either:

- fails spuriously on two of three platforms, or
- gets regenerated until it asserts nothing meaningful.

Neither is worth the maintenance cost, and the alternative already exists
here — assertions that verify behaviour, tokens and structure, which fail
for real reasons.

## Consequences

- Part 7 uses `test/unit/ui/widgets/group_{a,b,c}_test.dart` (19 assertions).
- Part 8 uses per-screen behaviour tests instead of goldens.
- The Part 6 guard test (`theme_test.dart`, no hardcoded colours) provides
  the visual-regression-adjacent coverage goldens would have given: it
  fails if any screen or widget reintroduces an inline colour.
- If pixel regression is genuinely required later, it needs a
  single-platform golden harness (e.g. Chrome-only), which is a separate
  decision.