#!/usr/bin/env bash

# Build, sign, notarize, and optionally publish the coordinated fxgl
# Moonlight/Sunshine macOS releases.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOONLIGHT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUNSHINE_DIR="${SUNSHINE_DIR:-${MOONLIGHT_DIR}/../Sunshine}"
COMMAND=""
MOONLIGHT_VERSION=""
SUNSHINE_VERSION=""
SIGNING_IDENTITY="${APPLE_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
QT_VERSION="6.11.1"
QT_BIN=""
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4')"
BOOTSTRAP=false
UNSIGNED=false
SKIP_NOTARIZATION=false
SKIP_TESTS=false

usage() {
  cat <<'EOF'
Build and publish coordinated macOS releases for the fxgl Moonlight/Sunshine forks.

Usage:
  scripts/release-forks.sh build [options]
  scripts/release-forks.sh publish [options]

Required:
  --moonlight-version VERSION    Numeric version, for example 6.1.1
  --sunshine-version VERSION     Numeric version, for example 2026.725.170000

Signing:
  --signing-identity ID          Developer ID Application identity with private key
  --notary-profile PROFILE       notarytool Keychain profile name
  --skip-notarization            Sign without notarizing or stapling
  --unsigned                     Unsigned build (not allowed with publish)

Other options:
  --sunshine-dir PATH            Sunshine checkout (default: ../Sunshine)
  --qt-bin PATH                  Official universal Qt bin directory
  --qt-version VERSION           Qt version for --bootstrap (default: 6.11.1)
  --jobs N                       Parallel build jobs
  --skip-tests                   Skip Sunshine tests
  --bootstrap                    Install build dependencies and official Qt
  -h, --help                     Show help

publish requires clean tracked trees. It commits only the Moonlight version
bump, builds and verifies everything, pushes moonlight-common-c before both
parents, creates version tags, and uploads both GitHub Releases.

Environment: APPLE_CODESIGN_IDENTITY, NOTARY_KEYCHAIN_PROFILE, SUNSHINE_DIR
EOF
}

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
need_value() { [[ -n "${2:-}" ]] || die "$1 requires a value"; }

validate_version() {
  [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "$1 must contain exactly three numeric components: $2"
}

clean_tree() {
  git -C "$1" diff --quiet --ignore-submodules=none -- &&
    git -C "$1" diff --cached --quiet --ignore-submodules=none --
}

require_clean_tree() {
  clean_tree "$1" || {
    git -C "$1" status --short --untracked-files=no >&2
    die "tracked changes must be committed before release: $1"
  }
}

bootstrap_dependencies() {
  log "Installing release dependencies"
  need brew
  brew install aqtinstall cmake doxygen graphviz node pkgconf \
    icu4c@78 miniupnpc openssl@3 opus llvm
  if ! create-dmg --help 2>&1 | grep -F -- '--no-version-in-filename' >/dev/null; then
    brew list create-dmg >/dev/null 2>&1 && brew unlink create-dmg
    npm install --global create-dmg@8.1.0
  fi
  local qt_root="${MOONLIGHT_DIR}/build/Qt"
  [[ -x "${qt_root}/${QT_VERSION}/macos/bin/qmake" ]] ||
    aqt install-qt mac desktop "${QT_VERSION}" clang_64 -O "${qt_root}"
}

resolve_qt() {
  [[ -n "${QT_BIN}" ]] || QT_BIN="${MOONLIGHT_DIR}/build/Qt/${QT_VERSION}/macos/bin"
  [[ -x "${QT_BIN}/qmake" ]] ||
    die "Qt not found at ${QT_BIN}; use --bootstrap or --qt-bin"
  local qt_core="${QT_BIN}/../lib/QtCore.framework/Versions/A/QtCore"
  [[ -f "${qt_core}" ]] || die "QtCore framework not found beside ${QT_BIN}"
  local archs
  archs="$(lipo -archs "${qt_core}")"
  [[ " ${archs} " == *" x86_64 "* && " ${archs} " == *" arm64 "* ]] ||
    die "Moonlight requires universal Qt (x86_64 + arm64), found: ${archs}"
}

check_signing() {
  if [[ "${UNSIGNED}" == true ]]; then
    [[ "${COMMAND}" != publish ]] || die "publish refuses unsigned releases"
    SKIP_NOTARIZATION=true
    return
  fi
  [[ -n "${SIGNING_IDENTITY}" ]] ||
    die "--signing-identity is required (a .cer without its private key is insufficient)"
  security find-identity -v -p codesigning | grep -F "\"${SIGNING_IDENTITY}\"" >/dev/null ||
    die "valid signing identity with private key not found: ${SIGNING_IDENTITY}"
  if [[ "${SKIP_NOTARIZATION}" == false ]]; then
    [[ -n "${NOTARY_PROFILE}" ]] ||
      die "--notary-profile is required unless --skip-notarization is used"
    xcrun --find notarytool >/dev/null 2>&1 ||
      die "notarytool not found; select full Xcode or use --skip-notarization"
    xcrun --find stapler >/dev/null 2>&1 || die "stapler not found"
  fi
}

check_submodules() {
  local mc="${MOONLIGHT_DIR}/moonlight-common-c/moonlight-common-c"
  local sc="${SUNSHINE_DIR}/third-party/moonlight-common-c"
  [[ -e "${mc}/.git" && -e "${sc}/.git" ]] || die "common submodules are not initialized"
  require_clean_tree "${mc}"
  require_clean_tree "${sc}"
  local mh sh
  mh="$(git -C "${mc}" rev-parse HEAD)"
  sh="$(git -C "${sc}" rev-parse HEAD)"
  [[ "${mh}" == "${sh}" ]] ||
    die "parents pin different moonlight-common-c commits: ${mh} vs ${sh}"
}

preflight() {
  [[ -e "${MOONLIGHT_DIR}/.git" ]] || die "Moonlight checkout not found"
  [[ -e "${SUNSHINE_DIR}/.git" ]] || die "Sunshine checkout not found: ${SUNSHINE_DIR}"
  validate_version "Moonlight version" "${MOONLIGHT_VERSION}"
  validate_version "Sunshine version" "${SUNSHINE_VERSION}"
  for cmd in git python3 cmake cpack create-dmg codesign security lipo hdiutil ditto shasum; do
    need "${cmd}"
  done
  create-dmg --help 2>&1 | grep -F -- '--no-version-in-filename' >/dev/null ||
    die "wrong create-dmg implementation; run again with --bootstrap"
  require_clean_tree "${MOONLIGHT_DIR}"
  require_clean_tree "${SUNSHINE_DIR}"
  check_submodules
  resolve_qt
  check_signing

  if [[ "${COMMAND}" == build ]]; then
    local current
    current="$(<"${MOONLIGHT_DIR}/app/version.txt")"
    [[ "${current}" == "${MOONLIGHT_VERSION}" ]] ||
      die "build does not edit sources: app/version.txt is ${current}, requested ${MOONLIGHT_VERSION}"
  else
    need gh
    gh auth status >/dev/null
  fi
}

prepare_moonlight_version() {
  local file="${MOONLIGHT_DIR}/app/version.txt"
  local current
  current="$(<"${file}")"
  [[ "${current}" != "${MOONLIGHT_VERSION}" ]] || return
  log "Updating Moonlight version ${current} -> ${MOONLIGHT_VERSION}"
  printf '%s\n' "${MOONLIGHT_VERSION}" >"${file}"
  git -C "${MOONLIGHT_DIR}" add app/version.txt
  git -C "${MOONLIGHT_DIR}" commit -m "chore: release v${MOONLIGHT_VERSION}"
}

check_tag_available() {
  local repo="$1" tag="$2" current existing remote
  current="$(git -C "${repo}" rev-parse HEAD)"
  if git -C "${repo}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    existing="$(git -C "${repo}" rev-list -n 1 "${tag}")"
    [[ "${existing}" == "${current}" ]] ||
      die "tag ${tag} already points to ${existing}, not current commit ${current}"
    return
  fi

  remote="$(git -C "${repo}" ls-remote --tags origin "refs/tags/${tag}" "refs/tags/${tag}^{}")"
  [[ -z "${remote}" ]] || die "tag ${tag} already exists on origin; fetch it before retrying"
}

check_publish_tags() {
  check_tag_available "${MOONLIGHT_DIR}" "v${MOONLIGHT_VERSION}"
  check_tag_available "${SUNSHINE_DIR}" "v${SUNSHINE_VERSION}"
}

build_moonlight() {
  log "Building Moonlight ${MOONLIGHT_VERSION} (universal macOS)"
  local signing="" profile=""
  [[ "${UNSIGNED}" == true ]] || signing="${SIGNING_IDENTITY}"
  [[ "${SKIP_NOTARIZATION}" == true ]] || profile="${NOTARY_PROFILE}"
  (
    cd "${MOONLIGHT_DIR}"
    PATH="${QT_BIN}:${PATH}" CI_VERSION="${MOONLIGHT_VERSION}" \
      SIGNING_IDENTITY="${signing}" NOTARY_KEYCHAIN_PROFILE="${profile}" \
      bash scripts/generate-dmg.sh Release
  )

  local app="${MOONLIGHT_DIR}/build/build-Release/app/Moonlight.app"
  local out="${MOONLIGHT_DIR}/build/installer-Release"
  local dmg="${out}/Moonlight-${MOONLIGHT_VERSION}.dmg"
  [[ -d "${app}" && -f "${dmg}" ]] || die "Moonlight artifacts were not produced"
  local archs
  archs="$(lipo -archs "${app}/Contents/MacOS/Moonlight")"
  [[ " ${archs} " == *" x86_64 "* && " ${archs} " == *" arm64 "* ]] ||
    die "Moonlight executable is not universal: ${archs}"
  if [[ "${UNSIGNED}" == false ]]; then
    codesign --verify --deep --strict --verbose=2 "${app}"
    codesign --verify --verbose=2 "${dmg}"
  fi
  if [[ "${SKIP_NOTARIZATION}" == false ]]; then
    xcrun stapler validate "${dmg}"
    spctl --assess --type open --context context:primary-signature -vv "${dmg}"
  fi
  local dsym="${out}/Moonlight-${MOONLIGHT_VERSION}.dsym"
  [[ ! -d "${dsym}" ]] || ditto -c -k --sequesterRsrc --keepParent \
    "${dsym}" "${out}/Moonlight-${MOONLIGHT_VERSION}-dSYM.zip"
  LC_ALL=C shasum -a 256 "${dmg}" >"${dmg}.sha256"
}

verify_dmg_app() {
  local dmg="$1" app_name="$2" assess="${3:-false}" mount_dir rc=0
  mount_dir="$(mktemp -d)"
  printf 'Y\n' | hdiutil attach -readonly -nobrowse -mountpoint "${mount_dir}" "${dmg}" >/dev/null
  codesign --verify --deep --strict --verbose=2 "${mount_dir}/${app_name}.app" || rc=$?
  if [[ "${assess}" == true ]]; then
    spctl --assess --type execute -vv "${mount_dir}/${app_name}.app" || rc=$?
  fi
  hdiutil detach "${mount_dir}" >/dev/null || rc=$?
  rmdir "${mount_dir}" || true
  return "${rc}"
}

build_sunshine() {
  log "Building Sunshine ${SUNSHINE_VERSION} ($(uname -m) macOS)"
  local build="${SUNSHINE_DIR}/cmake-build-release-fxgl"
  local branch commit sign=false
  branch="$(git -C "${SUNSHINE_DIR}" branch --show-current)"
  commit="$(git -C "${SUNSHINE_DIR}" rev-parse --short HEAD)"
  [[ "${UNSIGNED}" == true ]] || sign=true
  (
    cd "${SUNSHINE_DIR}"
    BRANCH="${branch}" BUILD_VERSION="${SUNSHINE_VERSION}" COMMIT="${commit}" \
      cmake -B "${build}" -S . -DBUILD_DOCS=OFF -DBUILD_TESTS=ON \
        -DBUILD_WERROR=ON -DCMAKE_BUILD_TYPE=Release -DSUNSHINE_ENABLE_TRAY=ON \
        -DSUNSHINE_PUBLISHER_NAME=fxgl \
        -DSUNSHINE_PUBLISHER_WEBSITE=https://github.com/fxgl/Sunshine \
        -DSUNSHINE_PUBLISHER_ISSUE_URL=https://github.com/fxgl/Sunshine/issues \
        -DAPPLE_CODESIGN_IDENTITY="${SIGNING_IDENTITY}"
    cmake --build "${build}" -j "${JOBS}"
    [[ "${SKIP_TESTS}" == true ]] ||
      "${build}/tests/test_sunshine" '--gtest_filter=-MouseInputs/*'
    if ! SHOULD_SIGN="${sign}" cpack -G DragNDrop --config "${build}/CPackConfig.cmake"; then
      log "Sunshine CPack failed; retrying once"
      SHOULD_SIGN="${sign}" cpack -G DragNDrop --config "${build}/CPackConfig.cmake" --verbose
    fi
  )

  local source="${build}/cpack_artifacts/Sunshine.dmg"
  local dir="${SUNSHINE_DIR}/artifacts"
  local dmg
  dmg="${dir}/Sunshine-${SUNSHINE_VERSION}-macOS-$(uname -m).dmg"
  [[ -f "${source}" ]] || die "Sunshine DMG was not produced"
  mkdir -p "${dir}"
  cp "${source}" "${dmg}"
  [[ "${UNSIGNED}" == true ]] || verify_dmg_app "${dmg}" Sunshine false
  if [[ "${SKIP_NOTARIZATION}" == false ]]; then
    xcrun notarytool submit "${dmg}" --keychain-profile "${NOTARY_PROFILE}" \
      --wait --timeout 15m
    xcrun stapler staple -v "${dmg}"
    xcrun stapler validate "${dmg}"
    verify_dmg_app "${dmg}" Sunshine true
  fi
  LC_ALL=C shasum -a 256 "${dmg}" >"${dmg}.sha256"
}

ensure_tag() {
  local repo="$1" tag="$2" target="$3" existing
  if git -C "${repo}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    existing="$(git -C "${repo}" rev-list -n 1 "${tag}")"
    [[ "${existing}" == "${target}" ]] ||
      die "tag ${tag} points to ${existing}, expected ${target}"
  else
    git -C "${repo}" tag -a "${tag}" -m "Release ${tag}" "${target}"
  fi
}

github_release() {
  local repo="$1" tag="$2" title="$3"
  shift 3
  if gh release view "${tag}" --repo "${repo}" >/dev/null 2>&1; then
    gh release upload "${tag}" --repo "${repo}" --clobber "$@"
  else
    gh release create "${tag}" --repo "${repo}" --verify-tag \
      --title "${title}" --generate-notes "$@"
  fi
}

publish_all() {
  log "Pushing coordinated repositories"
  local common="${MOONLIGHT_DIR}/moonlight-common-c/moonlight-common-c"
  local mb sb mt="v${MOONLIGHT_VERSION}" st="v${SUNSHINE_VERSION}"
  mb="$(git -C "${MOONLIGHT_DIR}" branch --show-current)"
  sb="$(git -C "${SUNSHINE_DIR}" branch --show-current)"
  [[ -n "${mb}" && -n "${sb}" ]] || die "parent repositories must be on branches"
  git -C "${common}" push origin HEAD:refs/heads/master
  git -C "${MOONLIGHT_DIR}" push origin "HEAD:refs/heads/${mb}"
  git -C "${SUNSHINE_DIR}" push origin "HEAD:refs/heads/${sb}"
  ensure_tag "${MOONLIGHT_DIR}" "${mt}" "$(git -C "${MOONLIGHT_DIR}" rev-parse HEAD)"
  ensure_tag "${SUNSHINE_DIR}" "${st}" "$(git -C "${SUNSHINE_DIR}" rev-parse HEAD)"
  git -C "${MOONLIGHT_DIR}" push origin "refs/tags/${mt}"
  git -C "${SUNSHINE_DIR}" push origin "refs/tags/${st}"

  log "Uploading GitHub Releases"
  local mo="${MOONLIGHT_DIR}/build/installer-Release"
  local ma=("${mo}/Moonlight-${MOONLIGHT_VERSION}.dmg" "${mo}/Moonlight-${MOONLIGHT_VERSION}.dmg.sha256")
  [[ ! -f "${mo}/Moonlight-${MOONLIGHT_VERSION}-dSYM.zip" ]] ||
    ma+=("${mo}/Moonlight-${MOONLIGHT_VERSION}-dSYM.zip")
  local sd
  sd="${SUNSHINE_DIR}/artifacts/Sunshine-${SUNSHINE_VERSION}-macOS-$(uname -m).dmg"
  github_release fxgl/moonlight-qt "${mt}" "Moonlight ${MOONLIGHT_VERSION} (fxgl)" "${ma[@]}"
  github_release fxgl/Sunshine "${st}" "Sunshine ${SUNSHINE_VERSION} (fxgl)" "${sd}" "${sd}.sha256"
}

parse_args() {
  [[ $# -gt 0 ]] || { usage; exit 2; }
  case "$1" in
    build|publish) COMMAND="$1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "first argument must be build or publish" ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --moonlight-version) need_value "$1" "${2:-}"; MOONLIGHT_VERSION="$2"; shift 2 ;;
      --sunshine-version) need_value "$1" "${2:-}"; SUNSHINE_VERSION="$2"; shift 2 ;;
      --signing-identity) need_value "$1" "${2:-}"; SIGNING_IDENTITY="$2"; shift 2 ;;
      --notary-profile) need_value "$1" "${2:-}"; NOTARY_PROFILE="$2"; shift 2 ;;
      --sunshine-dir) need_value "$1" "${2:-}"; SUNSHINE_DIR="$2"; shift 2 ;;
      --qt-bin) need_value "$1" "${2:-}"; QT_BIN="$2"; shift 2 ;;
      --qt-version) need_value "$1" "${2:-}"; QT_VERSION="$2"; shift 2 ;;
      --jobs) need_value "$1" "${2:-}"; JOBS="$2"; shift 2 ;;
      --bootstrap) BOOTSTRAP=true; shift ;;
      --unsigned) UNSIGNED=true; shift ;;
      --skip-notarization) SKIP_NOTARIZATION=true; shift ;;
      --skip-tests) SKIP_TESTS=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ -n "${MOONLIGHT_VERSION}" ]] || die "--moonlight-version is required"
  [[ -n "${SUNSHINE_VERSION}" ]] || die "--sunshine-version is required"
  [[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
}

main() {
  parse_args "$@"
  [[ "${BOOTSTRAP}" == false ]] || bootstrap_dependencies
  preflight
  [[ "${COMMAND}" != publish ]] || prepare_moonlight_version
  [[ "${COMMAND}" != publish ]] || check_publish_tags
  build_moonlight
  build_sunshine
  [[ "${COMMAND}" != publish ]] || publish_all
  log "Release workflow completed"
  printf 'Moonlight: %s\n' "${MOONLIGHT_DIR}/build/installer-Release/Moonlight-${MOONLIGHT_VERSION}.dmg"
  printf 'Sunshine:  %s\n' "${SUNSHINE_DIR}/artifacts/Sunshine-${SUNSHINE_VERSION}-macOS-$(uname -m).dmg"
}

main "$@"
