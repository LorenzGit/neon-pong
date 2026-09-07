#!/bin/bash
# Regenerates the project if needed, builds for the simulator and reinstalls.
set -e
cd "$(dirname "$0")/.."
DEV="$(cat /tmp/np_device)"
xcodebuild -project NeonPong.xcodeproj -scheme NeonPong \
  -destination "platform=tvOS Simulator,id=${DEV}" \
  -derivedDataPath build/DD CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD (SUCCEEDED|FAILED)" || true
xcrun simctl install "$DEV" build/DD/Build/Products/Debug-appletvsimulator/NeonPong.app
echo "installed"
