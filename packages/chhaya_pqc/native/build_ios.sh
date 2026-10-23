#!/bin/sh
set -eu

if [ "${PLATFORM_NAME:-}" = "" ] || [ "${CURRENT_ARCH:-}" = "" ]; then
  echo "Xcode must provide PLATFORM_NAME and CURRENT_ARCH for the AWS-LC iOS build." >&2
  exit 1
fi

sdk_name="${SDK_NAME:-$PLATFORM_NAME}"
deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
output_dir="${DERIVED_FILE_DIR:?}/chhaya-pqc/${sdk_name}-${CURRENT_ARCH}"
build_dir="$output_dir/cmake"
mkdir -p "$output_dir"

cmake -S "${PODS_TARGET_SRCROOT}/../native" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DCMAKE_OSX_ARCHITECTURES="$CURRENT_ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
cmake --build "$build_dir" --target chhaya_pqc --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"

provider_archive="$(find "$build_dir" -name libchhaya_pqc.a -type f -print -quit)"
crypto_archive="$(find "$build_dir/awslc" -name libcrypto.a -type f -print -quit)"
if [ -z "$provider_archive" ] || [ -z "$crypto_archive" ]; then
  echo "CMake did not produce both the Chhaya provider and pinned AWS-LC archives." >&2
  exit 1
fi

combined="$output_dir/libchhaya_pqc_combined.a"
temporary="$combined.tmp"
xcrun --sdk "$sdk_name" libtool -static -o "$temporary" "$provider_archive" "$crypto_archive"
mv -f "$temporary" "$combined"
