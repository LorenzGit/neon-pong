#!/bin/bash
# Fast type-check of every source file against the tvOS simulator SDK.
cd "$(dirname "$0")"
SDK=$(xcrun --sdk appletvsimulator --show-sdk-path)
out=$(xcrun --sdk appletvsimulator swiftc -typecheck \
  -target arm64-apple-tvos17.0-simulator -sdk "$SDK" \
  $(find Sources -name '*.swift') 2>&1)
if [ -n "$out" ]; then
  echo "$out" | head -${1:-60}
  exit 1
fi
echo "TYPECHECK CLEAN"
