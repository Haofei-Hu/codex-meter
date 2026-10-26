#!/bin/zsh
set -eu
ROOT=${0:A:h:h}
BUILD_DIR="${CODEX_METER_BUILD_DIR:-$ROOT/build}"
APP="$BUILD_DIR/Codex Meter.app/Contents/MacOS/CodexQuota"
[[ -x "$APP" ]] || "$ROOT/build.sh"
TEST_DIR="$BUILD_DIR/tests"
mkdir -p "$TEST_DIR"
"$APP" --desktop-test "$TEST_DIR/desktop"
"$APP" --self-test
"$APP" --work-test "$TEST_DIR/work"
"$APP" --integration-test "$TEST_DIR/accounts"
