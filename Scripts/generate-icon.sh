#!/bin/bash
set -euo pipefail

if [[ ! -f IMELock.xcodeproj/project.pbxproj ]]; then
    printf '%s\n' 'Run this script from the IMELock repository root.' >&2
    exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

mkdir -p build/icon-generation
xcrun swiftc -swift-version 6 -parse-as-library \
    IMELock/IconArtwork.swift Tools/GenerateIcon.swift -o build/icon-generation/GenerateIcon
build/icon-generation/GenerateIcon
printf '%s\n' 'Generated: IMELock/Assets.xcassets/AppIcon.appiconset'
