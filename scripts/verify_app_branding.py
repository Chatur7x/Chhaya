#!/usr/bin/env python3
"""Verify the Chhaya avatar and native launcher icon catalogs."""

import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Not a valid PNG: {path.relative_to(ROOT)}")
    return struct.unpack(">II", header[16:24])


def check_size(path: Path, expected: tuple[int, int]) -> None:
    if not path.is_file():
        raise ValueError(f"Missing branding asset: {path.relative_to(ROOT)}")
    actual = png_size(path)
    if actual != expected:
        raise ValueError(
            f"Wrong size for {path.relative_to(ROOT)}: expected {expected}, got {actual}"
        )


def main() -> int:
    try:
        source = ROOT / "assets/images/chhaya_avatar.png"
        check_size(source, (1254, 1254))

        android_sizes = {
            "mdpi": 48,
            "hdpi": 72,
            "xhdpi": 96,
            "xxhdpi": 144,
            "xxxhdpi": 192,
        }
        for density, size in android_sizes.items():
            check_size(
                ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
                (size, size),
            )

        icon_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        catalog = json.loads((icon_dir / "Contents.json").read_text(encoding="utf-8"))
        entries = catalog.get("images", [])
        if len(entries) < 18:
            raise ValueError(f"iOS app icon catalog has only {len(entries)} entries")
        for entry in entries:
            filename = entry.get("filename")
            if not filename:
                raise ValueError("iOS app icon entry is missing its filename")
            width, height = (float(value) for value in entry["size"].split("x"))
            scale = float(entry["scale"].removesuffix("x"))
            expected = (round(width * scale), round(height * scale))
            check_size(icon_dir / filename, expected)

        plist = (ROOT / "ios/Runner/Info.plist").read_text(encoding="utf-8")
        if "<key>CFBundleDisplayName</key>\n\t<string>Chhaya</string>" not in plist:
            raise ValueError("iOS display name must be Chhaya")
        manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(
            encoding="utf-8"
        )
        gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
        if 'android:icon="@mipmap/ic_launcher"' not in manifest:
            raise ValueError("Android launcher manifest does not reference ic_launcher")
        if 'manifestPlaceholders["appLabel"] = "Chhaya"' not in gradle:
            raise ValueError("Android release app label must be Chhaya")

        print(
            f"Branding verified: source avatar, {len(android_sizes)} Android launcher icons, "
            f"{len(entries)} iOS catalog icons, and Chhaya app labels."
        )
        return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"Branding verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
