#!/bin/bash
set -euo pipefail

build_arch="${1:-$(uname -m)}"
if [[ $# -gt 1 || ( "$build_arch" != arm64 && "$build_arch" != x86_64 ) ]]; then
    printf '%s\n' 'Usage: bash Scripts/build.sh [arm64|x86_64]' >&2
    exit 1
fi

if [[ ! -f IMELock.xcodeproj/project.pbxproj ]]; then
    printf '%s\n' 'Run this script from the IMELock repository root.' >&2
    exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ $# -eq 0 ]]; then
    derived_data=build/DerivedData
    output_app=build/IMELock.app
else
    derived_data="build/DerivedData-$build_arch"
    output_app="build/$build_arch/IMELock.app"
fi

xcodebuild -project IMELock.xcodeproj -scheme IMELock \
    -configuration Release -derivedDataPath "$derived_data" \
    -destination 'generic/platform=macOS' ARCHS="$build_arch" ONLY_ACTIVE_ARCH=YES -quiet build
rm -rf "$output_app"
ditto "$derived_data/Build/Products/Release/IMELock.app" "$output_app"
actual_arch=$(lipo -archs "$output_app/Contents/MacOS/IMELock")
if [[ "$actual_arch" != "$build_arch" ]]; then
    printf 'Unexpected architecture: %s\n' "$actual_arch" >&2
    exit 1
fi
codesign --verify --deep --strict "$output_app"
printf 'Built: %s (%s)\n' "$output_app" "$actual_arch"
