#!/bin/bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
    printf '%s\n' 'Usage: bash Scripts/package-release.sh' >&2
    exit 1
fi

for build_arch in arm64 x86_64; do
    bash Scripts/build.sh "$build_arch"
done

release_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/arm64/IMELock.app/Contents/Info.plist)
intel_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/x86_64/IMELock.app/Contents/Info.plist)
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "$release_version" != "$intel_version" ]]; then
    printf '%s\n' 'Both apps must have the same numeric major.minor.patch version.' >&2
    exit 1
fi

release_dir="build/releases/v$release_version"
mkdir -p "$release_dir"
release_stage=""
trap 'if [[ -n "$release_stage" ]]; then rm -rf "$release_stage"; fi' EXIT

for build_arch in arm64 x86_64; do
    release_stage=$(mktemp -d "$release_dir/.stage-$build_arch.XXXXXX")
    ditto "build/$build_arch/IMELock.app" "$release_stage/IMELock.app"
    ln -s /Applications "$release_stage/Applications"
    disk_image="$release_dir/IMELock-$release_version-$build_arch.dmg"
    hdiutil create -volname "IMELock $release_version ($build_arch)" \
        -srcfolder "$release_stage" -fs HFS+ -format UDZO -ov "$disk_image"
    hdiutil verify "$disk_image"
    rm -rf "$release_stage"
    release_stage=""
done

(
    cd "$release_dir"
    shasum -a 256 "IMELock-$release_version-arm64.dmg" "IMELock-$release_version-x86_64.dmg" > SHA256SUMS.txt
)
printf 'Packaged: %s\n' "$release_dir"
