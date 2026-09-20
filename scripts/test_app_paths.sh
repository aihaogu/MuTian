#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mutian-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc "$ROOT_DIR/MuTian/Support/AppPaths.swift" \
  "$ROOT_DIR/Tests/MuTianTests/AppPathsTests.swift" \
  -o "$TEST_DIR/app-paths-tests"
"$TEST_DIR/app-paths-tests"
