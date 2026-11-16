#!/usr/bin/env bash
# Builds a UNIVERSAL (arm64 + x86_64) KEYFLOW.app and packages it as a .dmg.
# Run on a Mac with Xcode or the Command Line Tools (Swift 5.9+):   ./scripts/build_dmg.sh
#
# Optional environment:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)"   # default: ad-hoc signature
#   NOTARY_PROFILE="my-notary-profile"                        # xcrun notarytool keychain profile
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="KEYFLOW"
EXEC_NAME="Keyflow"
OUT="dist"
APP="$OUT/$APP_NAME.app"
DMG="$OUT/$APP_NAME-universal.dmg"
SIGN_ID="${SIGN_ID:--}"

command -v swift >/dev/null || { echo "swift not found — install Xcode or: xcode-select --install"; exit 1; }
rm -rf "$OUT" .build/universal && mkdir -p "$OUT" .build/universal

# Keep the in-app uninstaller identical to scripts/uninstall.sh
{ echo '// GENERATED from scripts/uninstall.sh by scripts/build_dmg.sh — do not edit by hand.'
  echo 'let uninstallScriptSource = #"""'; cat scripts/uninstall.sh; echo '"""#'; } > Sources/Keyflow/UninstallScript.swift

echo "▶ Building arm64…"
swift build -c release --arch arm64
ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$EXEC_NAME"

echo "▶ Building x86_64…"
swift build -c release --arch x86_64
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$EXEC_NAME"

echo "▶ Merging with lipo…"
lipo -create "$ARM_BIN" "$X86_BIN" -output ".build/universal/$EXEC_NAME"
lipo -info ".build/universal/$EXEC_NAME"

echo "▶ Assembling $APP…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/universal/$EXEC_NAME" "$APP/Contents/MacOS/$EXEC_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -d Resources/AppIcon.iconset ]; then
  iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▶ Code signing (identity: $SIGN_ID)…"
if [ "$SIGN_ID" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi
codesign --verify --deep --strict "$APP" && echo "  signature OK"

echo "▶ Creating DMG (with 'Uninstall KEYFLOW' app)…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

UNI="$STAGE/Uninstall KEYFLOW.app"
APPLESCRIPT="$(mktemp -t keyflow-uninstall).applescript"
cat > "$APPLESCRIPT" <<'ASCRIPT'
on run
	set scriptPath to POSIX path of (path to resource "uninstall.sh")
	try
		do shell script "/bin/bash " & quoted form of scriptPath
	on error errMsg number errNum
		if errNum is not -128 then
			display dialog "KEYFLOW could not be uninstalled: " & errMsg & return & return & "You can also drag KEYFLOW from Applications to the Trash." buttons {"OK"} default button "OK" with icon stop
		end if
	end try
end run
ASCRIPT
osacompile -o "$UNI" "$APPLESCRIPT"
rm -f "$APPLESCRIPT"
cp scripts/uninstall.sh "$UNI/Contents/Resources/uninstall.sh"
chmod +x "$UNI/Contents/Resources/uninstall.sh"
if [ -d Resources/UninstallIcon.iconset ]; then
  iconutil -c icns Resources/UninstallIcon.iconset -o "$UNI/Contents/Resources/applet.icns"
fi
if [ "$SIGN_ID" = "-" ]; then
  codesign --force --deep --sign - "$UNI"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$UNI"
fi

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ "$SIGN_ID" != "-" ]; then
  codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "▶ Notarizing…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "✔ Done: $DMG"
lipo -archs "$APP/Contents/MacOS/$EXEC_NAME"
