#!/usr/bin/env bash
# Build NixClaw and install it on a connected iPhone.
#
# This used to be the tail of .github/workflows/build.yml, running on a
# self-hosted runner. It never belonged in CI: it needs a specific phone
# plugged into this Mac and a signing identity in this login keychain, and
# putting it in a workflow on a public repository meant a fork PR could reach
# the machine. CI now only proves the app compiles.
#
#   ./scripts/deploy-device.sh                 # use the default device below
#   DEVICE_ID=00008150-XXXX ./scripts/deploy-device.sh
#
# Config/Nix.xcconfig is gitignored and holds your real keys. Create it once
# by copying Config/NixClaw.xcconfig and filling in the values you want.
set -euo pipefail

DEVICE_ID="${DEVICE_ID:-00008150-000E22603CC2401C}"
SCHEME="NixClaw"
PROJECT="NixClaw.xcodeproj"
BUILD_DIR="build"

cd "$(dirname "$0")/.."

if [ ! -f Config/Nix.xcconfig ]; then
  echo "Config/Nix.xcconfig is missing. It is the base configuration for" >&2
  echo "every build config, so nothing compiles without it. Start from the" >&2
  echo "template:" >&2
  echo "" >&2
  echo "    cp Config/NixClaw.xcconfig Config/Nix.xcconfig" >&2
  echo "" >&2
  echo "then fill in your keys. It is gitignored and stays on this machine." >&2
  exit 1
fi

# Fail here with a clear message rather than inside xcodebuild, where a
# missing device surfaces as an unhelpful destination error.
if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE_ID"; then
  echo "Device $DEVICE_ID is not connected." >&2
  echo "Connected devices:" >&2
  xcrun devicectl list devices >&2 || true
  exit 1
fi

echo "Resolving packages..."
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"

echo "Building for device $DEVICE_ID..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR"

APP_PATH="$(find "$BUILD_DIR" -name "$SCHEME.app" -type d | head -1)"
if [ -z "$APP_PATH" ]; then
  echo "Build produced no $SCHEME.app under $BUILD_DIR/" >&2
  exit 1
fi

echo "Installing $APP_PATH..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
echo "Installed on $DEVICE_ID."
