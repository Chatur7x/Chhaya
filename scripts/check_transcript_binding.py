#!/usr/bin/env python3
"""Static transcript-binding gate for Chhaya v2 PQXDH (spec §6 criterion 14).

Fails (exit 1) if any of the following hold in production Dart code (lib/):

1. `buildTranscript` is defined in more than one file (T must have exactly
   one canonical builder: lib/core/crypto/pqc/transcript.dart).
2. Any `TranscriptFields(` constructor call outside transcript.dart.
3. Any HKDF call in a v2-path file that does not bind both `salt:` to
   SHA-256 of the transcript (via transcriptHash/hash256) and `info:` to a
   string starting with "Chhaya-PQXDH-v1" or "Chhaya-Classical-Fallback-v1"
   (the consent path).
4. A production messaging/ratchet file imports a v2 PQ module or the legacy
   PQXDH/DualKem scaffold (no Pqxdh/DualKem code path may compile-link into
   production messaging before WS3 binds the transcript into AEAD AD).
5. A §3.4 boundary string appears outside transcript.dart.

Exits 0 with a one-line summary when clean. Stdlib only.

WS3/WS5 note: when the v2 establishment is wired into the codec, adjust
MESSAGING_DENYLIST / MESSAGING_ALLOWLIST deliberately, with review - do not
silence this check ad hoc.
"""

import re
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "lib"
CANONICAL_BUILDER = LIB / "core" / "crypto" / "pqc" / "transcript.dart"

V2_PATH_TOKENS = (
    "pqxdh",
    "transcript",
    "negotiation",
    "prekey_bundle",
    "establishHybridV2",
    "acceptHybridV2",
    "deriveSessionKey",
    "deriveClassicalFallbackKey",
    "buildTranscript",
)

HKDF_CALL = re.compile(r"Hkdf\.deriveKey\s*\(")
BUILD_DEF = re.compile(r"Uint8List\s+buildTranscript\s*\(")
FIELDS_CTOR = re.compile(r"\bTranscriptFields\s*\(")
BOUNDARY_STRING = ("Chhaya-PQXDH-v1", "Chhaya-Classical-Fallback-v1")

# Production messaging/ratchet paths may not reference PQ modules before WS3
# binds the transcript into AEAD AD. Additions require a reviewed reason.
MESSAGING_DIRS = (
    Path("services") / "messaging",
    Path("core") / "crypto" / "ratchet",
)
MESSAGING_DENYLIST = (
    "pqxdh",
    "dual_kem",
    "hybrid_kex",
    "transcript",
    "negotiation",
    "prekey_bundle",
    "ml_kem",
    "ml_dsa",
    "pqc_provider",
)
MESSAGING_ALLOWLIST: tuple = ()

IMPORT_RE = re.compile(r"^import\s+'([^']+)'", re.MULTILINE)


def dart_files(root: Path):
    yield from sorted(root.rglob("*.dart"))


def call_text(source: str, start: int) -> str:
    """Return the argument text of the call whose '(' is at `start`."""
    depth = 0
    for i in range(start, len(source)):
        ch = source[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return source[start + 1 : i]
    return source[start:]  # unbalanced: the analyzer will flag it anyway


def line_of(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def main() -> int:
    violations = []

    builder_defs = [
        f
        for f in dart_files(LIB)
        if BUILD_DEF.search(f.read_text(encoding="utf-8", errors="replace"))
    ]
    if builder_defs != [CANONICAL_BUILDER]:
        names = ", ".join(str(f.relative_to(LIB.parent)) for f in builder_defs) or "none"
        violations.append(
            "transcript builder must live in exactly one file "
            f"({CANONICAL_BUILDER.relative_to(LIB.parent)}), found: {names}"
        )

    for path in dart_files(LIB):
        rel = path.relative_to(LIB.parent)
        source = path.read_text(encoding="utf-8", errors="replace")

        if path != CANONICAL_BUILDER and FIELDS_CTOR.search(source):
            for match in FIELDS_CTOR.finditer(source):
                violations.append(
                    f"{rel}:{line_of(source, match.start())}: TranscriptFields "
                    f"constructed outside the canonical builder"
                )

        if not any(token in source for token in V2_PATH_TOKENS):
            continue
        for match in HKDF_CALL.finditer(source):
            args = call_text(source, match.end() - 1)
            salt_ok = "salt:" in args and (
                "transcriptHash(" in args or "hash256(" in args
            )
            info_ok = "info:" in args and any(s in args for s in BOUNDARY_STRING)
            if not salt_ok:
                violations.append(
                    f"{rel}:{line_of(source, match.start())}: HKDF call in v2 path "
                    f"without salt = SHA-256(T) (salt arg must reference "
                    f"transcriptHash/hash256)"
                )
            if not info_ok:
                violations.append(
                    f"{rel}:{line_of(source, match.start())}: HKDF call in v2 path "
                    f"without normative info (\"Chhaya-PQXDH-v1\" or "
                    f"\"Chhaya-Classical-Fallback-v1\")"
                )

    for directory in MESSAGING_DIRS:
        base = LIB / directory
        if not base.is_dir():
            continue
        for path in dart_files(base):
            if path.name in MESSAGING_ALLOWLIST:
                continue
            source = path.read_text(encoding="utf-8", errors="replace")
            for match in IMPORT_RE.finditer(source):
                target = match.group(1).lower()
                if any(deny in target for deny in MESSAGING_DENYLIST):
                    violations.append(
                        f"{path.relative_to(LIB.parent)}: imports PQ module "
                        f"'{match.group(1)}' in a production messaging path "
                        f"(WS3 must bind T first)"
                    )

    for path in dart_files(LIB):
        rel = path.relative_to(LIB.parent)
        if path == CANONICAL_BUILDER:
            continue
        source = path.read_text(encoding="utf-8", errors="replace")
        if any(s in source for s in BOUNDARY_STRING):
            violations.append(
                f"{rel}: references a §3.4 boundary string outside transcript.dart"
            )

    if violations:
        print("check_transcript_binding: FAIL")
        for line in violations:
            print(f"  - {line}")
        return 1
    print(
        "check_transcript_binding: OK "
        f"(canonical builder pinned; {sum(1 for _ in dart_files(LIB))} files scanned)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
