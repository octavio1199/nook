#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh
open build/Nook.app
