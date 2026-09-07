#!/bin/bash
# Launches the app on the booted tvOS simulator with NP_* overrides and grabs a
# screenshot after a delay.
#   Tools/capture.sh <name> <delay-seconds> [KEY=VALUE ...]
set -e
cd "$(dirname "$0")/.."

NAME="$1"; DELAY="$2"; shift 2
DEV="$(cat /tmp/np_device)"
BUNDLE=com.lorenzonuvoletta.neonpong
OUT="artifacts/shots/${NAME}.png"
mkdir -p artifacts/shots

ENVARGS=()
for pair in "$@"; do
  ENVARGS+=("SIMCTL_CHILD_${pair}")
done

xcrun simctl terminate "$DEV" "$BUNDLE" >/dev/null 2>&1 || true
env "${ENVARGS[@]}" xcrun simctl launch "$DEV" "$BUNDLE" >/dev/null
python3 -c "import time,sys; time.sleep(float(sys.argv[1]))" "$DELAY"
xcrun simctl io "$DEV" screenshot --type=png "$OUT" >/dev/null 2>&1
echo "captured $OUT"
