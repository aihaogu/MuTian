#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mutian-stores.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc "$ROOT_DIR"/MuTian/Models/{Book,Classification,LibraryRoot,Selection,DownloadTask}.swift \
  "$ROOT_DIR"/MuTian/Support/{AppPaths,FileTypeDetector,NaturalSort,SnapshotWriter,DownloadLogStore}.swift \
  "$ROOT_DIR"/MuTian/Services/{LibraryPathRepair,FolderScanner,MetadataParser,PageRecordMerger}.swift \
  "$ROOT_DIR"/MuTian/Stores/{LibraryStore,DownloadTaskStore,SettingsStore}.swift \
  "$ROOT_DIR/Tests/StoreTests/StoreRegressionChecks.swift" -o "$TEST_DIR/store-checks"
"$TEST_DIR/store-checks"
