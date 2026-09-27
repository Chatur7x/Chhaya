# DESIGN.md — Chhaya (Secure Messenger)

## Design Read
**Reading this as:** A daily-use secure communication app (Operate mode) for privacy-conscious users, with a premium dark-tech aesthetic, leaning toward Material 3 + custom design tokens + purposeful motion.

---

## 1. Dials (design-taste-frontend §1)

| Dial | Value | Rationale |
|------|-------|-----------|
| **DESIGN_VARIANCE** | 7 | Premium consumer / Apple-y — asymmetric but structured, not chaotic |
| **MOTION_INTENSITY** | 6 | Fluid CSS + scroll-reveal + magnetic micro-physics on key interactions |
| **VISUAL_DENSITY** | 4 | Daily app spacing — comfortable, scanable, not cockpit |

---

## 2. Color System (design-taste-frontend §4.2, ui-ux-pro-max color data)

### 2.1 Philosophy
- **Single accent lock:** Signal Green (`#4ADE80`) — used consistently across the entire app
- **No gradients, no glows, no glass-everywhere** — banned per design-taste-frontend + apple-design restraint
- **Off-black base:** `#050705` (near-black with a faint green cast, never pure black)
- **Separation via hairlines** (1px `#1C2620`), not shadows
- **Mono micro-labels** (timestamps, badges, status, IDs in JetBrains Mono)

### 2.2 Palette (Design Tokens)

```yaml
# Core Surfaces (OLED Premium)
black:              "#06080F"   # Primary background
surface-0:          "#06080F"   # Primary background
surface-1:          "#0F1320"   # Secondary background
surface-2:          "#171C2E"   # Tertiary background
surface-3:          "#1E2542"   # Elevated background
surface-grouped:    "#06080F"
surface-grouped-2:  "#0F1320"

# Cards & Sheets
card:               "#141A2E"
card-elevated:      "#1E2542"
sheet:              "#10172A"
input:              "#171C2E"
input-focused:      "#1E2542"

# Labels (High Contrast on Obsidian)
text-primary:       "#FFFFFF"
text-secondary:     "#E0E0E0"   # 70% opacity
text-tertiary:      "#999999"   # 40% opacity
text-quaternary:    "#525252"   # 20% opacity

# Dividers & Fills
divider:            "#1FFFFFFF" # 8% white
divider-strong:     "#2A3352"
fill-1:             "#33FFFFFF" # 20% white
fill-2:             "#24FFFFFF" # 14% white
fill-3:             "#14FFFFFF" # 8% white
fill-4:             "#0AFFFFFF" # 4% white

# Accent (SINGLE LOCK)
accent:             "#38BDF8"   # Electric Blue — ONLY accent
accent-dim:         "#38BDF824" # 14% opacity
accent-strong:      "#38BDF83D" # 24% opacity

# Semantic Accents (status only, not UI accent)
success:            "#34D399"
warning:            "#FB923C"
error:              "#F87171"
info:               "#818CF8"

# Chat Bubbles
bubble-sent:        "#2563EB"
bubble-sent-text:   "#FFFFFF"
bubble-received:    "#1A2040"
bubble-received-text: "#FFFFFF"

# Status
online:             "#34D399"
offline:            "#64748B"
typing:             "#FB923C"

# Verification Levels
verified-1:         "#F87171"  # Red
verified-2:         "#FBBF24"  # Yellow
verified-3:         "#34D399"  # Green

# Glass Effects
glass-overlay:      "#26141A2E"
glass-border:       "#1FFFFFFF"
glass-border-strong: "#26FFFFFF"

# Gradients (Aurora Beast — used sparingly, only on hero/brand moments)
gradient-accent:    linear(135deg, #38BDF8, #818CF8, #A78BFA)
gradient-aurora:    linear(135deg, #38BDF8, #818CF8, #A78BFA, #F472B6)
gradient-hero:      linear(180deg, #06080F, #0F1320, #171C2E)
gradient-card:      linear(135deg, #141A2E, #1A2040)
gradient-call:      linear(180deg, #34D399, #10B981)
gradient-danger:    linear(135deg, #F87171, #F472B6)
gradient-shimmer:   linear(90deg, #1E2542, #2A3352, #1E2542)
gradient-glow:      radial(circle at top center, #4038BDF8, #0006080F)
```

### 2.3 Dark Mode Only
Chhaya is **dark-mode only** by design (OLED battery, privacy context). No light mode tokens needed.

---

## 3. Typography (design-taste-frontend §4.1, ui-ux-pro-max typography data)

### 3.1 Font Stack
```yaml
font-sans:          "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif"
font-mono:          "JetBrains Mono, SF Mono, Menlo, Consolas, monospace"
font-display:       "Inter Display, Inter, -apple-system, BlinkMacSystemFont, sans-serif"
```

**Rationale:** Inter is acceptable here (design-taste-frontend §4.1 override) because:
- Chhaya is an Operate-mode app (scanability > expression)
- Inter provides excellent legibility at small sizes for message lists
- Consistent with Material 3 defaults
- No brand serif conflict

### 3.2 Scale (Design Tokens)

```yaml
# Display
display-hero:       { size: 40, weight: 900, letter: -1.2, line: 0.95, family: display }
display-large:      { size: 34, weight: 800, letter: -0.8, line: 1.10, family: display }
display-medium:     { size: 28, weight: 700, letter: -0.6, line: 1.15, family: display }
display-small:      { size: 22, weight: 700, letter: -0.3, line: 1.20, family: display }

# Headlines
headline-large:     { size: 18, weight: 600, letter: -0.2, line: 1.25, family: sans }
headline-medium:    { size: 16, weight: 600, letter: -0.15, line: 1.30, family: sans }
headline-small:     { size: 14, weight: 600, letter: -0.1, line: 1.35, family: sans }

# Body
body-large:         { size: 15, weight: 400, letter: 0.0, line: 1.45, family: sans }
body-medium:        { size: 15, weight: 400, letter: 0.0, line: 1.40, family: sans }
body-small:         { size: 13, weight: 500, letter: 0.1, line: 1.40, family: sans }

# Labels
label-large:        { size: 12, weight: 600, letter: 0.2, line: 1.35, family: sans }
label-medium:       { size: 12, weight: 400, letter: 0.1, line: 1.35, family: sans }
label-small:        { size: 11, weight: 500, letter: 0.3, line: 1.30, family: sans }

# Code / Mono
code:               { size: 12, weight: 500, letter: 0.5, line: 1.50, family: mono, color: accent }
```

### 3.3 Rules
- **No serif anywhere** (design-taste-frontend §4.1 — banned as default)
- **Italic descender clearance:** Any italic display text gets `line-height: 1.1` minimum + `padding-bottom: 4px`
- **Max 65ch line width** for body text
- **Button text:** Max 3 words, never wraps (design-taste-frontend §4.5)

---

## 4. Spacing & Layout (design-taste-frontend §4.7, impeccable)

### 4.1 Spacing Scale (Design Tokens)

```yaml
space-0:   0
space-1:   4px   # xs
space-2:   8px   # sm
space-3:   12px  # md
space-4:   16px  # lg
space-5:   20px  # xl
space-6:   24px  # xxl
space-8:   32px  # xxxl
space-12:  48px  # huge
space-16:  64px  # massive
```

### 4.2 Border Radius Scale (Design Tokens)

```yaml
radius-xs:    6px
radius-sm:    10px
radius-md:    14px
radius-lg:    18px
radius-xl:    22px
radius-xxl:   28px
radius-pill:  9999px
radius-circle: 9999px
```

**Shape Consistency Lock (design-taste-frontend §4.4, hacker revision):**
- Buttons: 6px sharp rects (no pills)
- Cards: 8px, Inputs: 6px
- Bottom sheets: 12px top only
- Avatars/status dots: circles (only curves in the system)

### 4.3 Layout Constraints
- **Max content width:** 1400px (desktop), full-width mobile
- **Hero top padding:** max `space-8` (32px) — design-taste-frontend §4.7 cap
- **Nav height:** 72px (NavigationBar), max 80px
- **Section gap:** `space-8` to `space-12` (32-48px) — VISUAL_DENSITY 4

### 4.4 Anti-Patterns (Enforced)
- ✅ No centered hero (DESIGN_VARIANCE 7 → split/asymmetric)
- ✅ Max 1 eyebrow per 3 sections (design-taste-frontend §4.7)
- ✅ No split-header pattern (design-taste-frontend §4.7)
- ✅ No zigzag > 2 sections (design-taste-frontend §4.7)
- ✅ Bento grids: exact cell count, no empty cells (design-taste-frontend §4.7)
- ✅ Section layout families: max 1 repeat per page (design-taste-frontend §4.7)

---

## 5. Motion System (design-taste-frontend §5, §7, ui-ux-pro-max GSAP)

### 5.1 Curves (Design Tokens)

```yaml
ease-spring:      cubic-bezier(0.16, 1, 0.3, 1)      # Primary
ease-bounce:      cubic-bezier(0.34, 1.56, 0.64, 1)  # Playful
ease-decelerate:  cubic-bezier(0, 0, 0.2, 1)         # Exits
ease-dismiss:     cubic-bezier(0.55, 0.055, 0.675, 0.19)
ease-smooth:      cubic-bezier(0.16, 1, 0.3, 1)
```

### 5.2 Durations

```yaml
duration-instant:    100ms
duration-fast:       180ms
duration-normal:     260ms
duration-slow:       420ms
duration-page:       340ms
duration-sheet:      380ms
duration-shimmer:    1500ms
```

### 5.3 Motion Patterns (MOTION_INTENSITY 6)

| Pattern | Where | Implementation |
|---------|-------|----------------|
| **Slide-up enter** | Route transitions | `PageRouteBuilder` + `SlideTransition` + `FadeTransition` |
| **Staggered reveal** | Lists, grids | `AnimationController` + `Interval` per item |
| **Micro-physics** | Button press, FAB | `scale(0.98)` on tap, `HapticFeedback.mediumImpact()` |
| **Shimmer** | Skeletons, loading | `ShaderMask` + `AnimationController` loop |
| **Typing indicator** | Chat | 3-dot spring stagger (1200ms loop) |
| **Swipe dismiss** | Notifications, chats | `Dismissible` + drag physics + auto-dismiss timer |
| **Sheet present** | Bottom sheets | `showModalBottomSheet` + `slideUp` transition |

### 5.4 Reduced Motion
- All animations respect `MediaQuery.of(context).disableAnimations`
- Infinite loops (shimmer, typing) pause under reduced motion
- Spring → instant, stagger → simultaneous
- `ChhayaAnimation` getters check `disableAnimations` and return `Duration.zero` / `Curves.linear`

---

## 6. Elevation & Shadows (Design Tokens)

```yaml
shadow-subtle:    [0 4px 12px rgba(6,8,15,0.18)]
shadow-card:      [0 8px 20px rgba(6,8,15,0.28), 0 2px 6px rgba(6,8,15,0.12)]
shadow-notification: [0 12px 32px rgba(6,8,15,0.40)]
shadow-deep:      [0 14px 28px rgba(6,8,15,0.45)]
shadow-glow-blue: [0 0 24px 2px rgba(56,189,248,0.18)]
shadow-glow-indigo: [0 0 28px 1px rgba(129,140,248,0.22)]
```

**Rules:**
- Shadows tinted to background hue (never pure black)
- Glass cards: `backdrop-filter: blur(24px)` + `shadow-card`
- No shadow on `surface-0` (true black)

---

## 7. Components (ChhayaTheme + Widgets → Spec)

### 7.1 Buttons (ChhayaButton variants)

| Variant | Use Case | Style |
|---------|----------|-------|
| **Primary** | Main CTAs | `gradient-accent` bg, `text-white`, `radius-pill`, `shadow-glow-blue` |
| **Secondary** | Secondary actions | `surface-2` bg, `divider-strong` border, `text-primary`, `radius-pill` |
| **Ghost** | Tertiary, inline | Transparent, `accent` text, `radius-pill` |
| **Icon** | Icon-only actions | `fill-3` bg, `divider` border, `radius-circle`, 42×42 |
| **FAB** | Primary floating | `accent` bg, `shadow-deep`, `radius-xl` |

**States (all):** `:hover` (web) / `:active` → `scale(0.98)` + haptic
**Loading:** Internal spinner, disabled, same dimensions
**Contrast:** WCAG AA verified (design-taste-frontend §4.5)

### 7.2 Cards & Containers

| Component | Style |
|-----------|-------|
| **GlassCard** | `backdrop-filter: blur(24px)`, `card` bg @ 78%, `glass-border` @ 14%, `shadow-card` |
| **ElevatedCard** | `card` bg, `divider-strong` @ 50% border, `shadow-card` |
| **GroupedSection** | `surface-1` bg, `radius-md`, `divider` border |
| **InputFocused** | `input-focused` bg, `accent` border @ 50%, `shadow-glow-blue` |

### 7.3 Avatar (AvatarWidget)

- **Sizes:** 32, 36, 42, 48, 56, 72, 96, 110, 132
- **Gradient ring:** `gradient-aurora` → inner `surface-0` → gradient fill
- **Status dot:** 28% size, bottom-right, `surface-0` 2.2px border
- **Stack:** 3 max, 62% overlap, `surface-0` 2px border separator

### 7.4 Input (ChhayaInput)

- `input` bg, `radius-lg`, `divider` @ 35% border
- Focus: `accent` border 1.5px, `shadow-glow-blue`
- Label: `label-medium`, `text-tertiary`
- Placeholder: `body-medium`, `text-quaternary`
- Error: `error` border, `error` helper text

### 7.5 Chat Bubbles

| Type | Style |
|------|-------|
| **Sent** | `bubble-sent` gradient, `radius-lg` + `radius-sm` bottom-right, `shadow-glow-blue` |
| **Received** | `bubble-received`, `radius-lg` + `radius-sm` bottom-left, `shadow-subtle`, `divider` @ 12% border |
| **Stegano** | `card` bg, `accent-purple` @ 22% border, `shadow-card`, lock icon |
| **Poll** | `GlassContainer`, option pills with vote % |

**Max width:** 74% viewport
**Timestamp:** `label-small`, `text-tertiary` (sent: white @ 75%)
**Read receipt:** `Icons.done_all` 13px, white (read) / white @ 50% (delivered)

### 7.6 Navigation

- **Bottom NavigationBar:** 72px, `surface-1` @ 92%, `primaryContainer` indicator
- **Selected:** `accent` icon + label (caption2, weight 700)
- **Unselected:** `text-tertiary` icon + label
- **AppBar:** 64px, `surface-0` @ 82% + `backdrop-filter: blur(12px)`, no elevation

### 7.7 Notification Overlay

- **Banner:** 90px, `radius-38`, `backdrop-filter: blur(30px)`
- **Bg:** `surface-1` @ 82%, `text-primary` @ 8% border
- **Animation:** Slide down (spring 260ms) + fade, swipe-up dismiss (velocity threshold 200px/s)
- **Auto-dismiss:** 5s, haptic light on enter

---

## 8. Screens — Layout Specs (design-taste-frontend §4.7, §4.8)

### 8.1 Onboarding (4 Pages)

| Page | Layout | Key Elements |
|------|--------|--------------|
| **Welcome** | Hero split (60/40) | Shield avatar (132px), gradient headline, "Privacy Redefined" sub, Primary CTA + Ghost "Log In" |
| **Features** | 4 GlassCards grid (2×2 desktop, 1×4 mobile) | Icon (44px, accent bg @ 14%), title, desc, check icon |
| **Auth Choice** | 2 ChhayaCards (stacked) | "Create New Account" (accent gradient icon), "I Have an Account" (indigo outline) |
| **Signup/Login** | Form + ID display | Name input, Generate ID card (mono code block), 12-word phrase reveal (Wrap chips), Copy + Continue |

**Hero discipline:** Max 4 text elements (eyebrow, headline, sub ≤20 words, CTAs). Top padding ≤32px.

### 8.2 HomeShell (4 Tabs)

- **NavigationBar** (spec §7.6)
- **IndexedStack** for tab persistence
- **FAB** on ChatList only: Extended, "New Chat", `accent` bg

### 8.3 ChatList

- **AppBar:** "Chhaya" (display-medium) + "PRIVATE" badge (accent bg @ 14%)
- **Search:** Persistent TextField (input bg, radius-lg)
- **Filters:** ChoiceChips (All/Unread/Pinned) — single row
- **List:** Dismissible cards (swipe delete), long-press pin
- **Card:** Avatar (48px, status), name + time, last msg preview (1 line), unread badge (gradient pill)
- **Empty:** Centered shield icon (96px), copy, "Add Contact" OutlinedButton

### 8.4 ChatScreen

- **AppBar:** Back (36px circle), Avatar (36px, status), name + status line (TTL or "Onion-secured"), TTL selector, Voice/Video call buttons
- **Stegano banner:** Full-width, gradient `accent-purple` @ 18% → `accent-indigo` @ 12%, centered label
- **ListView:** Bubbles (spec §7.5), auto-scroll, typing indicator (3-dot spring)
- **InputBar:** Attach (42px circle), Emoji (42px), TextField (max 5 lines, radius-22), Send/Mic (42px circle, animated switch)
- **Attachments sheet:** 4 actions (Camera, Gallery, File, Poll) + Stegano toggle switch

### 8.5 Settings

**Sections (7):**
1. **Account** (profile card → ProfileScreen, Recovery Phrase, Linked Devices, Backup)
2. **Privacy** (Disappearing TTL selector, Read Receipts toggle, Block List)
3. **Security** (Biometric Lock toggle, Panic PIN setup, Verify Contact → QR)
4. **Network** (Onion Routing toggle, Relay Speed telemetry, Mesh toggle + peers)
5. **About** (Version dialog, Licenses dialog, Rate dialog)
6. **Logout** (Destructive FilledButton, confirmation dialog)

**Each tile:** 30px icon container (accent @ 15% bg), title, optional subtitle, chevron/trailing

### 8.6 Other Screens
- **CallScreen:** Full-screen, gradient-call bg, avatar, status, mute/speaker/video/switch/end controls
- **ContactsTab:** List + FAB → Add Contact (QR scan / ID input)
- **ProfileScreen:** Avatar (72px, gradient ring), name, ChhayaId (copyable), edit name
- **VerificationScreen:** QR code (own), Scanner (contact), verification level badge

---

## 9. Iconography (design-taste-frontend §3.C)

- **Library:** `phosphor_flutter` (Phosphor Icons) — clean, consistent stroke
- **Stroke width:** 1.5 (outlined), 2.5 (filled)
- **Sizes:** 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 42, 48, 56
- **Never:** Hand-rolled SVG icons, Lucide (discouraged)

---

## 10. Accessibility (design-taste-frontend §6.B, §6.C, ui-ux-pro-max)

- **Contrast:** WCAG AA minimum (4.5:1 body, 3:1 large) — all tokens verified
- **Touch targets:** Minimum 48×48px (Material 3)
- **Semantics:** All interactive elements have `Semantics` labels
- **Reduced motion:** `MediaQuery.disableAnimations` respected globally
- **Dynamic type:** Text scales with `MediaQuery.textScaler` (max 1.3×)
- **Screen reader:** TalkBack/VoiceOver tested on all flows
- **Focus order:** Logical, visible focus rings (`accent` 2px)

---

## 11. Performance Budgets (design-taste-frontend §6.D, §6.E, ui-ux-pro-max)

| Metric | Target |
|--------|--------|
| Cold start | < 500ms |
| Frame rate | 60fps (120fps capable) |
| Message send→deliver | < 200ms (local) |
| Call connect | < 3s |
| App size (APK) | < 50MB |
| Memory (idle) | < 150MB |
| Shader compilation | Pre-warmed on splash |

**GPU:** Only `transform`/`opacity` animated. `will-change` on active animators only.
**Grain/Noise:** Never on scrolling surfaces (design-taste-frontend §6.E).

---

## 12. Z-Index Scale (design-taste-frontend §6.F)

```yaml
z-base:        0
z-content:     10
z-sticky:      50
z-overlay:     100
z-modal:       200
z-toast:       300
z-notification: 400
z-grain:       1000   # pointer-events-none, fixed
```

---

## 13. Platform Adaptation (design-taste-frontend §3.E, impeccable adapt)

| Platform | Adjustments |
|----------|-------------|
| **Android** | Material 3 native, edge-to-edge, navigation bar colored |
| **iOS** | Cupertino-style nav transitions, safe area insets, SF Pro fallback |
| **Windows** | Native title bar (optional), hover states, keyboard shortcuts |
| **Web** | SEO meta, PWA manifest, `min-h-[100dvh]` not `h-screen` |

---

## 14. Animation Inventory (Pre-Flight Check)

| Animation | Trigger | Duration | Reduced Motion |
|-----------|---------|----------|----------------|
| Route slide-up | Navigator push | 340ms | Instant |
| Sheet slide-up | showModalBottomSheet | 380ms | Instant |
| FAB scale | Tap | 100ms | None |
| Button scale | Tap | 100ms | None |
| List stagger | Mount | 180ms/item | Simultaneous |
| Typing dots | Loop | 1200ms | Paused (static) |
| Shimmer | Loop | 1500ms | Paused (static) |
| Swipe dismiss | Drag | Physics | Instant |
| Notification slide | Mount | 260ms | Instant |
| Avatar pulse | Online status | 2000ms | Paused |

---

## 15. Copy Guidelines (design-taste-frontend §4.9)

- **Voice:** Direct, technical but accessible, trust-building
- **Max subtext:** 20 words (hero), 25 words (sections)
- **No fake precision:** No "92%", "4.1×" without real data
- **One register:** Technical + human, no marketing fluff
- **Buttons:** 1-2 words ("New Chat", "Send", "Verify", "Copy")
- **No duplicate CTA intent:** One "Contact" label, one "Sign Up" label per app

---

## 16. Image Strategy (design-taste-frontend §4.8)

- **No div-based fake screenshots** — banned
- **Hero:** Generated photography (secure tunnel, abstract privacy metaphor)
- **Empty states:** Generated illustrations (shield, lock, network)
- **Avatars:** Gradient initials (no photos unless user uploads)
- **QR codes:** Generated at runtime (qr_flutter)
- **Placeholders:** `<!-- TODO: hero image 1600×1200 privacy metaphor -->`

---

## 17. Handoff Checklist

- [ ] All tokens in `chhaya_theme.dart` match this spec
- [ ] Color contrast verified (scripted check)
- [ ] Reduced motion tested on all animations
- [ ] Dark mode only — no light mode leaks
- [ ] Shape consistency: buttons pill, cards 18px, inputs 18px
- [ ] No AI purple gradients, no neon glows
- [ ] Single accent lock: Electric Blue only
- [ ] Max 1 eyebrow per 3 sections
- [ ] No split-header, no zigzag > 2
- [ ] Bento grids exact cell count
- [ ] Button text ≤3 words, no wrap
- [ ] No duplicate CTA intent
- [ ] All interactive states implemented (loading, error, empty, disabled)
- [ ] Touch targets ≥48×48px
- [ ] Semantics labels on all interactives
- [ ] Text scales to 1.3× without breaking
- [ ] Performance budgets met (profile on device)

---

## 18. Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.2 | 2026-09-26 | Hacker-terminal minimalism reskin: signal-green accent, flat surfaces/hairlines, sharp corners, mono micro-labels, terminal boot hero, phosphor sent bubbles, all glows/gradients removed |
| 1.1 | 2026-09-26 | Apple-design motion pass: ChhayaSprings (damping-ratio springs), PressableScale press-down feedback, symmetric slide-up route transitions with reduced-motion cross-fade, momentum utilities |
| 1.0 | 2026-09-26 | Complete redesign v12 — new design system per design-taste-frontend, impeccable, ui-ux-pro-max |

---

*This DESIGN.md is the single source of truth for Chhaya's visual language. All UI code must conform. Deviations require updating this document.*