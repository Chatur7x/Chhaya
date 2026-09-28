# Security Policy

## Threat model

Chhaya protects message content and metadata against network observers,
compromised servers, and device coercion:

- End-to-end encryption (X25519 + AES-256-GCM, Double Ratchet)
- Post-quantum hybrid key exchange (X25519 + ML-KEM-1024, V14)
- Onion-routed transport (3-hop, region-diverse circuits)
- No phone number, email, or central identity
- Coercion resistance (duress PIN, decoy vault, V14)

Out of scope: endpoint compromise with unlocked device, rubber-hose
attacks beyond the duress design, quantum attacks against classical
signatures before the ML-DSA migration completes.

## Reporting a vulnerability

**Do not open public issues for security bugs.**

Email the maintainers privately with:
1. Affected version / commit
2. Steps to reproduce (proof of concept preferred)
3. Impact assessment

We aim to acknowledge within 72 hours and ship a fix within 30 days.
Credit is given with reporter consent.

## Cryptography policy

- Only audited primitives: X25519, Ed25519, AES-256-GCM, HKDF-SHA256,
  PBKDF2-HMAC-SHA256, SHA-256/512, ML-KEM-1024, ML-DSA-87.
- No custom ciphers, no ECB, no nonce reuse, no `Random()` for secrets.
- New protocol code (ratchet, handshake, mesh) requires external audit
  before release — see the V14 roadmap.
