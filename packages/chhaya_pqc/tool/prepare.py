"""Fetch the approved immutable AWS-LC source and prepare symbol namespacing.

Only generated files below the caller's build cache are written. No secret or
application data is accepted. This is a build-time tool, never app startup code.
"""
from __future__ import annotations
import argparse
import hashlib
import platform
from pathlib import Path
import subprocess
import tarfile
import urllib.request

COMMIT = "fa9bc8d6f7cfb2cf849b247fb06bbbfc41ecc9d6"
SHA256 = "7b1c746a69ae7b55ca0b46408593ee630de54909abbd15a18ebcfd110b931a32"
URL = f"https://github.com/aws/aws-lc/archive/{COMMIT}.tar.gz"


def run(args: list[str], cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def source(cache: Path) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "aws-lc.tar.gz"
    if not archive.exists():
        temporary = archive.with_suffix(".download")
        with urllib.request.urlopen(URL, timeout=120) as response, temporary.open("wb") as out:
            while chunk := response.read(1024 * 1024):
                out.write(chunk)
        temporary.replace(archive)
    with archive.open("rb") as downloaded:
        if hashlib.file_digest(downloaded, "sha256").hexdigest() != SHA256:
            raise RuntimeError("AWS-LC source checksum mismatch; refusing to build")
    # Keep the checkout path short: Android's Windows CMake/Ninja toolchain
    # can fail on generated source paths beyond the legacy MAX_PATH limit.
    # The download is still bound to COMMIT and SHA256 above.
    extracted = cache / "aws-lc"
    archive_root = cache / f"aws-lc-{COMMIT}"
    if not (extracted / ".chhaya-verified").exists():
        if not (archive_root / "CMakeLists.txt").exists():
            with tarfile.open(archive, "r:gz") as contents:
                contents.extractall(cache, filter="data")
        if not extracted.exists():
            archive_root.rename(extracted)
        (extracted / ".chhaya-verified").write_text(SHA256, encoding="ascii")
    return extracted


def prepare(args: argparse.Namespace) -> None:
    cache = Path(args.cache).resolve()
    src = source(cache / "source")
    bootstrap = cache / "bootstrap"
    symbols = cache / "symbols.txt"
    flags = ["-DCMAKE_BUILD_TYPE=Release", "-DBUILD_TESTING=OFF", "-DBUILD_TOOL=OFF",
             "-DBUILD_LIBSSL=OFF", "-DDISABLE_PERL=ON", "-DDISABLE_GO=ON",
             "-DENABLE_SOURCE_MODIFICATION=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
    if args.ninja:
        flags += ["-GNinja", f"-DCMAKE_MAKE_PROGRAM={args.ninja}"]
    if args.toolchain:
        flags += [f"-DCMAKE_TOOLCHAIN_FILE={args.toolchain}"]
    if args.abi:
        flags += [f"-DANDROID_ABI={args.abi}", f"-DANDROID_PLATFORM={args.api}", "-DANDROID_STL=c++_static"]
    if args.sdk:
        flags += ["-DCMAKE_SYSTEM_NAME=iOS", f"-DCMAKE_OSX_SYSROOT={args.sdk}",
                  f"-DCMAKE_OSX_ARCHITECTURES={args.arch}", "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0"]
    marker = hashlib.sha256((SHA256 + repr(flags)).encode()).hexdigest()
    stamp = cache / "bootstrap.sha256"
    if not symbols.exists() or not stamp.exists() or stamp.read_text() != marker:
        run([args.cmake, "-S", str(src), "-B", str(bootstrap), *flags])
        run([args.cmake, "--build", str(bootstrap), "--target", "crypto", "--parallel", "4"])
        libraries = list(bootstrap.rglob("libcrypto.a"))
        if len(libraries) != 1:
            raise RuntimeError("Expected one bootstrap crypto archive")
        fmt = "elf" if args.abi else "macho" if args.sdk or platform.system() == "Darwin" else "elf"
        run([args.go, "run", "./util/read_symbols.go", "-obj-file-format", fmt,
             "-out", str(symbols), str(libraries[0])], cwd=src)
        stamp.write_text(marker, encoding="ascii")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", required=True)
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--go", default="go")
    parser.add_argument("--ninja", default="")
    parser.add_argument("--toolchain", default="")
    parser.add_argument("--abi", default="")
    parser.add_argument("--api", default="android-23")
    parser.add_argument("--sdk", default="")
    parser.add_argument("--arch", default="arm64")
    prepare(parser.parse_args())
