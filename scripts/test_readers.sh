#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mutian-readers.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc "$ROOT_DIR"/MuTian/Models/{Book,Classification,LibraryRoot}.swift \
  "$ROOT_DIR"/MuTian/Support/{AppPaths,FileTypeDetector,NaturalSort}.swift \
  "$ROOT_DIR"/MuTian/Services/{LibraryPathRepair,TextFileLoader,EpubArchive,FolderScanner,MetadataParser}.swift \
  "$ROOT_DIR/Tests/ReaderTests/ReaderRegressionChecks.swift" -o "$TEST_DIR/reader-checks"
"$TEST_DIR/reader-checks" "$@"
