#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-pets-regression.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

if [[ ! -x /usr/bin/sqlite3 ]]; then
  echo "Missing /usr/bin/sqlite3, cannot run codex-pet regression tests" >&2
  exit 1
fi

swift test -c release --build-path "${BUILD_DIR}/package-build"

swiftc \
  -swift-version 6 \
  "${ROOT_DIR}/Sources/CodexPets/DetailPresentation.swift" \
  "${ROOT_DIR}/Sources/CodexPets/Models.swift" \
  "${ROOT_DIR}/Sources/CodexPets/UsageRefreshState.swift" \
  "${ROOT_DIR}/Sources/CodexPets/DetailPanelMetrics.swift" \
  "${ROOT_DIR}/Sources/CodexPets/ScreenSafeAreaGeometry.swift" \
  "${ROOT_DIR}/Sources/CodexPets/AppInfo.swift" \
  "${ROOT_DIR}/Sources/CodexPets/Formatters.swift" \
  "${ROOT_DIR}/Sources/CodexPets/RateLimitResetCredits.swift" \
  "${ROOT_DIR}/Sources/CodexPets/ResetCreditsIndicator.swift" \
  "${ROOT_DIR}/Sources/CodexPets/SnapshotOutputFormatter.swift" \
  "${ROOT_DIR}/Sources/CodexPets/Shell.swift" \
  "${ROOT_DIR}/Sources/CodexPets/CodexSessionEventDecoder.swift" \
  "${ROOT_DIR}/Sources/CodexPets/CodexPetsSettings.swift" \
  "${ROOT_DIR}/Sources/CodexPets/CodexUsageStore.swift" \
  "${ROOT_DIR}/Tests/CodexPetsRegressionTests/main.swift" \
  -o "${BUILD_DIR}/CodexPetsRegressionTests"

"${BUILD_DIR}/CodexPetsRegressionTests"
