# Chhaya Cryptography (V14 Part 1)

## Layout

```
lib/core/crypto/
├── chhaya_crypto_engine.dart   # Facade: stable public API
└── primitives/
    ├── x25519.dart             # RFC 7748 key agreement
    ├── ed25519.dart            # RFC 8032 signatures
    ├── aes_gcm.dart            # AES-256-GCM AEAD, nonce||ct||tag wire format
    ├── hkdf.dart               # RFC 5869 (deriveKey, derive64, expand)
    ├── pbkdf2.dart             # Account key stretching (100k iterations)
    ├── sha.dart                # SHA-256/512 + hex helpers
    ├── rng.dart                # Fortuna CSPRNG + Csprng.wipe zeroization
    └── bip39.dart              # Spec-compliant mnemonics, 2048-word list
```

## Rules

- All algorithms live in `primitives/`. The engine only delegates.
- Keys are zeroized after use (`ChhayaKeyPair.dispose`, `Csprng.wipe`).
- Nonces are random per encryption, never reused with the same key.
- Tampered AES-GCM input throws — never returns unauthenticated data.

## Test vectors

`test/unit/crypto/primitives_test.dart` pins every primitive to
published vectors: FIPS 180-4 (SHA), RFC 5869 TC1 (HKDF), RFC 8018
(PBKDF2), RFC 7748 §6.1 (X25519 DH both directions), RFC 8032 §7.1
(Ed25519 key + signature), BIP-39 zero-entropy vector. AES-GCM is
cross-validated against the independent `cryptography` package
implementation with fixed key/nonce, plus tamper and wrong-key
rejection tests and 10k-nonce uniqueness sampling.
