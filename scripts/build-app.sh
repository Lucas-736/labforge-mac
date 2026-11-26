#!/usr/bin/env bash
#
# build-app.sh — LabForge（研铸）build, package, sign & DMG pipeline.
#
# Pure SwiftPM pipeline (no Xcode project, no xcodebuild):
#   1. Unit tests (CLT Swift Testing aware) with a hard "tests actually ran" assertion
#   2. swift build -c release
#   3. Generate dist/AppIcon.icns via scripts/generate-icon.swift
#   4. Assemble dist/LabForge.app (Info.plist, binary, icon)
#   5. Ad-hoc code sign + verify
#   6. Package dist/LabForge.dmg
#   7. Optional: install to /Applications (--install)
#
# Usage:
#   ./scripts/build-app.sh [--install] [--skip-tests] [--version 1.0.0] [--build-number 1]
#

set -euo pipefail

# --- Defaults ---------------------------------------------------------------
VERSION="1.0.0"
BUILD_NUMBER="1"
INSTALL=0
SKIP_TESTS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/LabForge.app"
DMG_PATH="${DIST_DIR}/LabForge.dmg"
APP_ICON="${DIST_DIR}/AppIcon.icns"
TEST_LOG="${DIST_DIR}/swift-test.log"

cd "${PROJECT_ROOT}"

# --- Argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=1
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "error: --version requires a value" >&2
        exit 2
      fi
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      if [[ $# -lt 2 ]]; then
        echo "error: --build-number requires a value" >&2
        exit 2
      fi
      BUILD_NUMBER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--install] [--skip-tests] [--version <ver>] [--build-number <num>]"
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

human_size() {
  # human_size <path> → "1.2M" style size string
  local path="$1"
  if [[ -e "${path}" ]]; then
    du -sh "${path}" | awk '{print $1}'
  else
    echo "?"
  fi
}

step() {
  printf '\n\033[1;38;2;204;120;92m==>\033[0m %s\n' "$1"
}

# --- 1. Unit tests ----------------------------------------------------------
if [[ "${SKIP_TESTS}" -eq 0 ]]; then
  step "Running unit tests (swift test)…"

  CLT_DIR="$(xcode-select -p 2>/dev/null || true)"
  CLT_TESTING_FRAMEWORK="/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework"

  mkdir -p "${DIST_DIR}"
  : > "${TEST_LOG}"

  test_args=()
  if [[ "${CLT_DIR}" == "/Library/Developer/CommandLineTools" && -d "${CLT_TESTING_FRAMEWORK}" ]]; then
    echo "CLT-only toolchain detected — enabling CLT Swift Testing framework path."
    # CLT ships Testing.framework + lib_TestingInterop.dylib outside the default
    # search paths (see Package.swift). The auto-generated test runner module
    # does not inherit per-target flags, so the framework path must be passed
    # on the command line as well — otherwise zero tests run (silently).
    test_args=(-Xswiftc -F -Xswiftc "${CLT_TESTING_FRAMEWORK%/Testing.framework}")
  fi
  if swift test ${test_args[@]+"${test_args[@]}"} 2>&1 | tee "${TEST_LOG}"; then
    :
  else
    statuses=("${PIPESTATUS[@]}")
    echo "error: test pipeline failed (swift test exit ${statuses[0]}, tee exit ${statuses[1]}). Log: ${TEST_LOG}" >&2
    exit 1
  fi

  # Hard assertion: tests actually ran (guards against the silent 0-tests CLT trap).
  if ! grep -Eq 'Test run with [1-9][0-9]* tests.*passed' "${TEST_LOG}"; then
    echo "error: no passing tests were detected in ${TEST_LOG} — refusing to package." >&2
    echo "------- tail of test log -------" >&2
    tail -n 20 "${TEST_LOG}" >&2
    exit 1
  fi
  grep -E 'Test run with [1-9][0-9]* tests.*passed' "${TEST_LOG}" | tail -n 1
else
  step "Skipping unit tests (--skip-tests)."
fi

# --- 2. Release build --------------------------------------------------------
step "Building release binary (swift build -c release)…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
if [[ ! -x "${BIN_DIR}/LabForge" ]]; then
  echo "error: expected executable not found at ${BIN_DIR}/LabForge" >&2
  exit 1
fi
echo "Binary: ${BIN_DIR}/LabForge"

# --- 3. App icon --------------------------------------------------------------
step "Generating app icon (dist/AppIcon.icns)…"
swift "${SCRIPT_DIR}/generate-icon.swift" "${APP_ICON}"
if [[ ! -s "${APP_ICON}" ]]; then
  echo "error: ${APP_ICON} missing or empty" >&2
  exit 1
fi
echo "Icon: ${APP_ICON} ($(human_size "${APP_ICON}"))"

# --- 4. Assemble the .app -----------------------------------------------------
step "Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_DIR}/LabForge" "${APP_BUNDLE}/Contents/MacOS/LabForge"
chmod +x "${APP_BUNDLE}/Contents/MacOS/LabForge"
cp "${APP_ICON}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>LabForge</string>
	<key>CFBundleDisplayName</key>
	<string>LabForge</string>
	<key>CFBundleIdentifier</key>
	<string>com.labforge.app</string>
	<key>CFBundleExecutable</key>
	<string>LabForge</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © LabForge. All rights reserved.</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
</dict>
</plist>
PLIST
plutil -lint "${APP_BUNDLE}/Contents/Info.plist"
echo "Info.plist written (version ${VERSION}(${BUILD_NUMBER}))."

# --- 5. Ad-hoc code signing ---------------------------------------------------
step "Ad-hoc code signing…"
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"
echo "Signature verified."

# --- 6. DMG packaging ---------------------------------------------------------
step "Packaging ${DMG_PATH}…"
DMG_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/labforge-dmg.XXXXXX")"
cleanup() {
  [[ -n "${DMG_STAGING:-}" && -d "${DMG_STAGING}" ]] && rm -rf "${DMG_STAGING}"
}
trap cleanup EXIT

ditto "${APP_BUNDLE}" "${DMG_STAGING}/LabForge.app"
ln -s /Applications "${DMG_STAGING}/Applications"

rm -f "${DMG_PATH}"
if diskutil image create from --help 2>&1 | grep -q -- '--volumeName'; then
  diskutil image create from --volumeName "LabForge" --format UDZO "${DMG_STAGING}" "${DMG_PATH}" >/dev/null
else
  hdiutil create -volname "LabForge" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
fi
echo "DMG: ${DMG_PATH} ($(human_size "${DMG_PATH}"))"

# --- 7. Optional install -------------------------------------------------------
if [[ "${INSTALL}" -eq 1 ]]; then
  step "Installing to /Applications/LabForge.app…"
  rm -rf /Applications/LabForge.app
  ditto "${APP_BUNDLE}" /Applications/LabForge.app
  echo "Installed: /Applications/LabForge.app"
fi

# --- 8. Summary ---------------------------------------------------------------
step "Build complete."
cat <<SUMMARY
  App bundle : ${APP_BUNDLE} ($(human_size "${APP_BUNDLE}"))
  App icon   : ${APP_ICON} ($(human_size "${APP_ICON}"))
  DMG        : ${DMG_PATH} ($(human_size "${DMG_PATH}"))
  Version    : ${VERSION} (${BUILD_NUMBER})
  Install    : $( [[ "${INSTALL}" -eq 1 ]] && echo "/Applications/LabForge.app" || echo "skipped (use --install)" )
SUMMARY
