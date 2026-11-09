#!/bin/bash
set -euo pipefail

if [[ ! -f IMELock.xcodeproj/project.pbxproj ]]; then
    printf '%s\n' 'Run this script from the IMELock repository root.' >&2
    exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

probe_arch="${IMELOCK_TEST_ARCH:-$(uname -m)}"
if [[ "$probe_arch" != arm64 && "$probe_arch" != x86_64 ]]; then
    printf '%s\n' 'IMELOCK_TEST_ARCH must be arm64 or x86_64.' >&2
    exit 1
fi
if [[ -z "${IMELOCK_TEST_ARCH:-}" ]]; then
    probe=build/IntegrationProbe.app
else
    probe="build/$probe_arch/IntegrationProbe.app"
fi
mkdir -p "$probe/Contents/MacOS"
cp Tools/IntegrationInfo.plist "$probe/Contents/Info.plist"
xcrun swiftc -swift-version 6 -O -target "$probe_arch-apple-macos14.0" \
    IMELock/Core/*.swift IMELock/InputSourceService.swift IMELock/LockController.swift \
    Tools/IntegrationProbe.swift -o "$probe/Contents/MacOS/IntegrationProbe"
codesign --force --sign - --options runtime --entitlements Config/IMELock.entitlements "$probe"
"$probe/Contents/MacOS/IntegrationProbe" "$@"
