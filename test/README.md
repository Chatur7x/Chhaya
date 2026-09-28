# Chhaya Test Layout

```
test/
├── unit/            # Fast, hermetic unit tests (no devices, no network)
│   └── crypto/      # Primitive vectors, engine facade, ratchet (Part 1+4)
├── widget/          # Widget + golden tests (Part 7+8)
├── integration/     # End-to-end flows (Part 8+)
├── chhaya_advanced_test.dart  # V13 legacy suite (kept passing, do not delete)
└── widget_test.dart           # V13 legacy suite (kept passing, do not delete)
```

Rules:
- New crypto tests go in `test/unit/crypto/`.
- New UI tests go in `test/widget/` with golden files beside them.
- Never delete a passing test. Fix forward.
- `flutter test` must stay green on every commit.
