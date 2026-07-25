#!/usr/bin/env bash
# This script requires create-dmg to be installed from https://github.com/sindresorhus/create-dmg
BUILD_CONFIG=$1

fail()
{
	echo "$1" 1>&2
	exit 1
}

if [ "$BUILD_CONFIG" != "Debug" ] && [ "$BUILD_CONFIG" != "Release" ]; then
  fail "Invalid build configuration - expected 'Debug' or 'Release'"
fi

BUILD_ROOT=$PWD/build
SOURCE_ROOT=$PWD
BUILD_FOLDER=$BUILD_ROOT/build-$BUILD_CONFIG
INSTALLER_FOLDER=$BUILD_ROOT/installer-$BUILD_CONFIG

if [ -n "$CI_VERSION" ]; then
  VERSION=$CI_VERSION
else
  VERSION=$(<"$SOURCE_ROOT/app/version.txt")
fi

if [ "$SIGNING_PROVIDER_SHORTNAME" == "" ]; then
  SIGNING_PROVIDER_SHORTNAME=$SIGNING_IDENTITY
fi
if [ "$SIGNING_IDENTITY" == "" ]; then
  SIGNING_IDENTITY=$SIGNING_PROVIDER_SHORTNAME
fi

[ "$SIGNING_IDENTITY" == "" ] || git diff-index --quiet HEAD -- || fail "Signed release builds must not have unstaged changes!"

echo Updating dependencies
python3 "$SOURCE_ROOT/setup-deps.py"

echo Cleaning output directories
rm -rf "$BUILD_FOLDER"
rm -rf "$INSTALLER_FOLDER"
mkdir -p "$BUILD_ROOT"
mkdir -p "$BUILD_FOLDER"
mkdir -p "$INSTALLER_FOLDER"

# Enable LTO for official builds
export CFLAGS=-flto=thin
export CXXFLAGS=-flto=thin
export LDFLAGS=-flto=thin

echo Configuring the project
pushd "$BUILD_FOLDER" || fail "Unable to enter build folder"
qmake "$SOURCE_ROOT/moonlight-qt.pro" QMAKE_APPLE_DEVICE_ARCHS="x86_64 arm64" || fail "Qmake failed!"
# Generate recursive Makefiles and the .moc files included directly by C++
# sources before starting the parallel build. qmake does not reliably order
# these targets when a clean recursive build is run with a high -j value.
make qmake_all || fail "Qmake Makefile generation failed!"
CONFIG_LOWER=$(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')
make -C app -f "Makefile.$BUILD_CONFIG" \
  "$CONFIG_LOWER/computermanager.moc" \
  "$CONFIG_LOWER/boxartmanager.moc" \
  "$CONFIG_LOWER/computermodel.moc" || fail "MOC generation failed!"
popd || fail "Unable to leave build folder"

echo Compiling Moonlight in "$BUILD_CONFIG" configuration
pushd "$BUILD_FOLDER" || fail "Unable to enter build folder"
make -j"$(sysctl -n hw.logicalcpu)" "$CONFIG_LOWER" || fail "Make failed!"
popd || fail "Unable to leave build folder"

echo Saving dSYM file
pushd "$BUILD_FOLDER" || fail "Unable to enter build folder"
dsymutil app/Moonlight.app/Contents/MacOS/Moonlight -o "Moonlight-$VERSION.dsym" || fail "dSYM creation failed!"
cp -R "Moonlight-$VERSION.dsym" "$INSTALLER_FOLDER" || fail "dSYM copy failed!"
popd || fail "Unable to leave build folder"

echo Creating app bundle
EXTRA_ARGS=()
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS+=("-use-debug-libs"); fi
echo Extra deployment arguments: "${EXTRA_ARGS[@]}"
LC_ALL=en_US.UTF-8 macdeployqt "$BUILD_FOLDER/app/Moonlight.app" "${EXTRA_ARGS[@]}" \
  -qmldir="$SOURCE_ROOT/app/gui" -appstore-compliant -no-codesign || fail "macdeployqt failed!"

# Qt deploys all SQL drivers when QtSql is pulled in by QML LocalStorage. The
# Mimer driver is unused by Moonlight and references a proprietary library that
# is not part of the Qt SDK, so it must not ship in the bundle.
rm -f "$BUILD_FOLDER/app/Moonlight.app/Contents/PlugIns/sqldrivers/libqsqlmimer.dylib"

echo Removing dSYM files from app bundle
find "$BUILD_FOLDER/app/Moonlight.app/" -name '*.dSYM' -exec rm -rf {} +

if [ "$SIGNING_IDENTITY" != "" ]; then
  echo Signing app bundle
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$BUILD_FOLDER/app/Moonlight.app" || fail "Signing failed!"
fi

echo Creating DMG
if [ "$SIGNING_IDENTITY" != "" ]; then
  create-dmg "$BUILD_FOLDER/app/Moonlight.app" "$INSTALLER_FOLDER" --identity="$SIGNING_IDENTITY" --no-version-in-filename || fail "create-dmg failed!"
else
  create-dmg "$BUILD_FOLDER/app/Moonlight.app" "$INSTALLER_FOLDER" --no-version-in-filename --no-code-sign
  case $? in
    0) ;;
    2) ;;
    *) fail "create-dmg failed!";;
  esac
fi

if [ "$NOTARY_KEYCHAIN_PROFILE" != "" ]; then
  echo Uploading to App Notary service
  xcrun notarytool submit --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait "$INSTALLER_FOLDER/Moonlight.dmg" || fail "Notary submission failed"

  echo Stapling notary ticket to DMG
  xcrun stapler staple -v "$INSTALLER_FOLDER/Moonlight.dmg" || fail "Notary ticket stapling failed!"
fi

mv "$INSTALLER_FOLDER/Moonlight.dmg" "$INSTALLER_FOLDER/Moonlight-$VERSION.dmg"
echo Build successful
