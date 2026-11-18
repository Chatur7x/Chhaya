#!/bin/sh
set -eu

if [ "${PLATFORM_NAME:-}" = "" ]; then
  echo "Xcode must provide PLATFORM_NAME for the AWS-LC iOS build." >&2
  exit 1
fi

sdk_name="${SDK_NAME:-$PLATFORM_NAME}"
deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
archs="${ARCHS:-}"
if [ -z "$archs" ] || [ "$archs" = "undefined_arch" ]; then
  archs="${NATIVE_ARCH_ACTUAL:-${CURRENT_ARCH:-}}"
fi
if [ -z "$archs" ] || [ "$archs" = "undefined_arch" ]; then
  echo "Xcode did not provide a usable ARCHS, NATIVE_ARCH_ACTUAL, or CURRENT_ARCH." >&2
  exit 1
fi

output_dir="${DERIVED_FILE_DIR:?}/chhaya-pqc/${sdk_name}"
mkdir -p "$output_dir"

set --
for arch in $archs; do
  arch_dir="$output_dir/$arch"
  build_dir="$arch_dir/cmake"
  mkdir -p "$arch_dir"
  cmake -S "${PODS_TARGET_SRCROOT}/../native" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
  cmake --build "$build_dir" --target chhaya_pqc --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"

  provider_archive="$(find "$build_dir" -name libchhaya_pqc.a -type f -print -quit)"
  crypto_archive="$(find "$build_dir/awslc" -name libcrypto.a -type f -print -quit)"
  if [ -z "$provider_archive" ] || [ -z "$crypto_archive" ]; then
    echo "CMake did not produce both the Chhaya provider and pinned AWS-LC archives for $arch." >&2
    exit 1
  fi

  combined="$arch_dir/libchhaya_pqc_combined.a"
  temporary="$combined.tmp"
  xcrun --sdk "$sdk_name" libtool -static -o "$temporary" "$provider_archive" "$crypto_archive"
  mv -f "$temporary" "$combined"
  set -- "$@" "$combined"
done

universal="$output_dir/libchhaya_pqc_combined.a"
xcrun lipo -create "$@" -output "$universal"
