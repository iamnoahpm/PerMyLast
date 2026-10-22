#!/usr/bin/env bash
# NFR-1 / AC-12: fail if anything looks like an Anthropic API key.
# Usage: scripts/check-secrets.sh [extra path ...]   (e.g. a built .app bundle)
# Matches key-shaped strings only, so the "sk-ant-…" placeholder text in the UI is fine.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pattern='sk-ant-[A-Za-z0-9_-]{20,}'
found=0
scan() { if grep -rEIl "$pattern" "$@" 2>/dev/null; then found=1; fi; }
scan "$root" --exclude-dir=.git --exclude-dir=build --exclude-dir=.build --exclude-dir=node_modules --exclude-dir=.swiftpm
for extra in "$@"; do scan "$extra"; done
if [ "$found" = 1 ]; then echo "FAIL: key-shaped string found in the files above"; exit 1; fi
echo "OK: no Anthropic key found"
