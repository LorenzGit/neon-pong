#!/bin/bash
# Builds the project for the simulator and reinstalls only after a successful build.
set -eo pipefail
cd "$(dirname "$0")/.."
DEV="$(cat /tmp/np_device)"
xcodebuild -project NeonPong.xcodeproj -scheme NeonPong \
  -destination "platform=tvOS Simulator,id=${DEV}" \
  -derivedDataPath build/DD CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | awk '/error:|warning: .*\.swift|BUILD (SUCCEEDED|FAILED)/'
xcrun simctl install "$DEV" build/DD/Build/Products/Debug-appletvsimulator/NeonPong.app
echo "installed"
