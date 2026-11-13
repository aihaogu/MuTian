#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mutian-metadata.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc "$ROOT_DIR"/MuTian/Models/{Book,Classification}.swift \
  "$ROOT_DIR"/MuTian/Support/{FileTypeDetector,AppPaths}.swift \
  "$ROOT_DIR"/MuTian/Stores/SettingsStore.swift \
  "$ROOT_DIR"/MuTian/Services/{BookNameParser,MetadataParser,BookRecognition,LibraryCSV,OnlineBookLookup}.swift \
  "$ROOT_DIR/Tests/MetadataTests/MetadataRegressionChecks.swift" -o "$TEST_DIR/metadata-checks"
"$TEST_DIR/metadata-checks"
