# Chhaya V14 — current product definition

**Product:** Chhaya, a privacy-focused messenger prototype
**Client:** Flutter for Android and iOS, with additional repository targets
**Account:** Chhaya identity key and recovery phrase; no phone number or email is required by the app account model
**Visual identity:** Warm cream and coral, Departure Mono for the established display treatment, and the Chhaya crescent/chat avatar.

## Product promise

Chhaya aims to let people communicate without tying the app account to a phone number or email. Current code includes direct and group encrypted-message flows, identity verification controls, replies, attachments, polls, disappearing-message controls, local search/pin/block features, call signaling, app lock, local encrypted storage and encrypted export/restore scaffolding.

This is an active development project. A feature in the code is not considered production-ready until its acceptance evidence is recorded in [the delivery checklist](docs/delivery-checklist.md). Current build, hosted-backend, device-test and security-review limitations are listed there.

## Security wording

Use precise statements only:

- Direct chat encryption currently uses Chhaya's custom X25519/Double Ratchet/AES-GCM implementation. It has not received an independent protocol audit.
- ML-KEM/ML-DSA primitives are present, but the live messaging protocol does not yet use authenticated post-quantum key establishment or ratchet reseeding.
- The onion-router prototype is not connected to normal message delivery.
- The backend can observe account/conversation relationships and delivery metadata while it stores encrypted envelopes.
- Device security, backups, push notifications, background calls, and production deployment require further platform work and validation.

Do not use “military grade,” “unbreakable,” “zero knowledge,” “anonymous,” “no central server,” or intelligence-agency comparisons as product guarantees. A protocol name, dependency or design goal is not evidence of a deployed protection.

## Current feature boundaries

The app provides the user flows represented in the repository, subject to the open checks in the delivery checklist. It does not currently provide verified sealed sender, a production onion network, complete device pairing/revocation, background incoming-call integration, SFrame media encryption, production push delivery, or a deployed SaaS backend with an owned domain and operational database. Group participant addition/invitation still needs a secure acceptance and key-session flow.

## Product quality goals

- Keep Android and iOS behavior aligned and accessible.
- Respect reduced-motion settings and use platform-appropriate interaction patterns.
- Keep local data encrypted and explain backup/recovery trade-offs.
- Make identity verification, session encryption level, membership changes and delivery state understandable to users.
- Measure startup time, message latency, media throughput, battery and resource use on named physical devices before publishing performance claims.
