#!/usr/bin/env bash
# Runs the test suite. With Command Line Tools only, SwiftPM sometimes fails to find
# the Testing macro plugin, so point it there explicitly when it exists.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ -d "$PLUGINS" ]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  swift test "$@"
fi
