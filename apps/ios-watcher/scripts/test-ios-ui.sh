#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/WatcherIOS.xcodeproj"
SCHEME="${IOS_SCHEME:-WatcherIOS}"

check_xcode_ready() {
  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    echo "Xcode first-launch setup is incomplete."
    echo "Run: sudo xcodebuild -runFirstLaunch"
    exit 1
  fi
}

resolve_simulator_name() {
  if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    echo "$IOS_SIMULATOR_NAME"
    return
  fi

  local detected
  detected="$(xcrun simctl list devices available | awk -F ' \\(' '/^[[:space:]]*iPhone /{gsub(/^[[:space:]]+/, "", $1); print $1; exit}')"
  if [[ -z "$detected" ]]; then
    echo "No available iPhone simulator device found."
    exit 1
  fi
  echo "$detected"
}

check_xcode_ready

if ! xcrun simctl list runtimes | grep -q "iOS"; then
  echo "No iOS Simulator runtime found."
  echo "Install one from Xcode > Settings > Components, then rerun tests."
  exit 1
fi

SIMULATOR_NAME="$(resolve_simulator_name)"
DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${IOS_SIMULATOR_OS:-latest}}"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:WatcherIOSUITests \
  test
