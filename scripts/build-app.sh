#!/bin/sh
# Builds the Taggart app bundle.
#
#   scripts/build-app.sh
#       For your own Mac: build/Taggart.app, native architecture, ad-hoc signed.
#   scripts/build-app.sh --release
#       For other people: a universal (Apple silicon + Intel) build, packaged as
#       build/Taggart-<version>.zip and build/Taggart-<version>.dmg (with an
#       Applications shortcut to drag the app to). Ad-hoc signed unless --sign.
#   scripts/build-app.sh --sign "Developer ID Application: Name (TEAMID)"
#       Signs with that certificate, with the hardened runtime.
#   scripts/build-app.sh --sign "…" --notarize <profile>
#       Also has Apple notarize the release, stapling the tickets to the app
#       and the disk image.
#       <profile> is a notarytool keychain profile, created once with:
#       xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
#
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
set -eu
cd "$(dirname "$0")/.."

usage() {
    sed -n '2,18s/^# \{0,1\}//p' "$0"
}

die() {
    echo "error: $*" >&2
    exit 1
}

release=0
identity=""
profile=""
while [ $# -gt 0 ]; do
    case "$1" in
        --release) release=1 ;;
        --sign)
            [ $# -ge 2 ] || die "--sign needs a signing identity"
            identity="$2"
            shift
            ;;
        --notarize)
            [ $# -ge 2 ] || die "--notarize needs a notarytool keychain profile"
            profile="$2"
            release=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown option: $1"
            ;;
    esac
    shift
done

if [ -n "$profile" ] && [ -z "$identity" ]; then
    die "--notarize needs --sign: Apple only notarizes apps signed with a Developer ID certificate"
fi
if [ -n "$identity" ] && ! security find-identity -v -p codesigning | grep -qF "\"$identity\""; then
    die "no signing certificate named \"$identity\" in the keychain (see: security find-identity -v -p codesigning)"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

# Build.
if [ "$release" = 1 ]; then
    arch_flags="--arch arm64 --arch x86_64"
else
    arch_flags=""
fi
# shellcheck disable=SC2086 # word splitting of arch_flags is intended
swift build -c release --product Taggart $arch_flags
# shellcheck disable=SC2086
bin="$(swift build -c release --product Taggart $arch_flags --show-bin-path)"

# Assemble the bundle.
app=build/Taggart.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$bin/Taggart" "$app/Contents/MacOS/Taggart"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# The licenses of Taggart and the libraries built into it.
cp LICENSE "$app/Contents/Resources/Licenses/Taggart-MIT.txt"
cp THIRD_PARTY_NOTICES.md Resources/Licenses/*.txt "$app/Contents/Resources/Licenses/"

# Sign.
if [ -n "$identity" ]; then
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
echo "Built $app ($(lipo -archs "$app/Contents/MacOS/Taggart"), version $version)"

[ "$release" = 1 ] || exit 0

# Submits a file to Apple's notary service and waits for the verdict.
notarize() {
    echo "Submitting $1 to Apple for notarization (this usually takes a few minutes)…"
    log="$(mktemp)"
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait | tee "$log"
    if ! grep -q "status: Accepted" "$log"; then
        rm -f "$log"
        die "notarization of $1 failed; see why with: xcrun notarytool log <submission id> --keychain-profile $profile"
    fi
    rm -f "$log"
}

# The zip, notarized if asked; the app then gets the ticket stapled to it.
zip="build/Taggart-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
if [ -n "$profile" ]; then
    notarize "$zip"
    xcrun stapler staple "$app"
    # Re-zip so the download contains the stapled ticket.
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    spctl --assess --type execute --verbose "$app"
fi
echo "Packaged $zip"

# The disk image: the (stapled) app plus an Applications shortcut.
dmg="build/Taggart-$version.dmg"
staging="$(mktemp -d)"
ditto "$app" "$staging/Taggart.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "Taggart $version" -srcfolder "$staging" -format UDZO -ov "$dmg"
rm -rf "$staging"
if [ -n "$identity" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
fi
if [ -n "$profile" ]; then
    notarize "$dmg"
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi
echo "Packaged $dmg"

if [ -z "$identity" ]; then
    echo "Note: ad-hoc signed. On other Macs, people must allow it once in"
    echo "System Settings → Privacy & Security → Open Anyway."
fi
