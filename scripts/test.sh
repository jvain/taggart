#!/bin/sh
# Runs the test suite. With only the Command Line Tools installed, SwiftPM
# doesn't find Swift Testing's macro plugin by itself, so point it there.
set -eu
cd "$(dirname "$0")/.."
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
