# Chhaya mobile design system

The user approved warm cream and coral, calm and minimal, on 23 October 2026. This replaces the legacy terminal design. Product UI is Operate mode: messages, people, and the next useful action lead.

## Visual language

Cream #F5F4EF is the canvas; white and warm off-white separate surfaces. Ink #1F1E1B carries primary text; #6B6862 carries secondary text. Coral #D97757 remains a decorative brand primitive. Interactive coral #A84D34 provides normal-text contrast with white; never use the decorative coral behind small white text. Coral tint #F5E5DD groups supporting information and avatars. Status always has a text label.

Inter is bundled under the SIL Open Font License and used for both headings and controls. Bundled Roboto Mono is reserved for identity strings. Font names without assets are not design decisions. Body copy uses 16sp where reading is the task. Labels use 13–14sp; headings use 24–36sp. Respect system text scaling; avoid forcing essential content into fixed-height cards.

Use a 4dp spacing rhythm, 24dp screen gutters, 16dp related-content spacing, and 24–32dp section spacing. List rows are separated by hairlines rather than independent shadowed cards. Surfaces use 12–16dp corners; functional grouped controls can use pills. No decorative blur, neon glow, terminal readouts, or invented security statistics.

## Navigation and components

Four destinations: Chats, Calls, Contacts, Settings. Phone navigation is a bottom bar; expanded widths at 720dp use a rail and constrain the content measure. Preserve native back navigation and keyboard insets. Chat actions use a labeled overflow menu at narrow widths. The composer always displays a send affordance, disabled when there is no text or a send is pending; it never pretends an unavailable microphone works.

Conversation rows show identity, preview, time, unread count, and accessible options. Pin/delete actions are available without relying on hidden gestures. Deleting local history requires confirmation and explains remote resynchronization. Contacts search by name or full ID. Calls describe foreground requirements. Settings retain account, connection, privacy, and security controls in consistent groups.

## Product truth

Onboarding describes implemented identity, verification, encryption, and server connection. It must not present onion routing, decentralized files, audited anonymity, or complete background calling as available. Unsupported attachments have an explanatory sheet rather than a grid of apparently working actions. Verification status derives from actual contact state.

The approved warm light surface is the app default. Legacy dark theme APIs remain for compatibility; a complete semantic dark migration is a separate task. Mixing a dark Material theme with hardcoded light surfaces is prohibited.

## Verification

Render actual Flutter screens at 360dp, 320dp with 200% text, and 768dp. Capture loading/error states, voice calling, the adaptive app shell, chats, contacts, calls, settings, onboarding, signup, restore, conversation, profile, and verification. Review one batched set, repair defects together, and confirm once. Unit tests check primary-action and message text contrast, layout exceptions, and existing behavioral regressions. Physical Android/iPhone screen-reader, keyboard, camera, and call testing is still necessary; screenshot tests are not a claim of full WCAG conformance.
