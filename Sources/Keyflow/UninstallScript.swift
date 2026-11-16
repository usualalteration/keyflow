// GENERATED from scripts/uninstall.sh by scripts/build_dmg.sh — do not edit by hand.
let uninstallScriptSource = #"""
#!/bin/bash
# KEYFLOW uninstaller.
# Removes the app, its preferences/caches and its Input Monitoring permission.
# Used three ways:
#   1. standalone:            ./uninstall.sh            (works for every KEYFLOW version)
#   2. from the app:          menu bar icon / app menu → "Uninstall KEYFLOW…"
#   3. from the DMG:          double-click "Uninstall KEYFLOW"
# Files you exported (WAV recordings) are never touched.

BUNDLE_ID="app.keyflow.KEYFLOW"
EXEC_NAME="Keyflow"
YES=0
APP_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) YES=1 ;;
    --app) APP_ARG="${2:-}"; shift ;;
  esac
  shift
done

say() {   # message; shown in Terminal if there is one, otherwise as a dialog
  if [ -t 1 ]; then echo "$1"; else
    osascript -e 'on run argv' -e 'display dialog (item 1 of argv) with title "KEYFLOW" buttons {"OK"} default button "OK"' -e 'end run' "$1" >/dev/null 2>&1
  fi
}

confirm() {
  if [ -t 0 ]; then
    printf '%s [y/N] ' "$1"; read -r a; [ "$a" = "y" ] || [ "$a" = "Y" ]
  else
    osascript -e 'on run argv' -e 'display dialog (item 1 of argv) with title "KEYFLOW" buttons {"Cancel","Uninstall"} default button "Cancel" with icon caution' -e 'end run' "$1" >/dev/null 2>&1
  fi
}

# Locate installed copies
APPS=()
if [ -n "$APP_ARG" ] && [ -d "$APP_ARG" ]; then APPS+=("$APP_ARG"); fi
for c in "/Applications/KEYFLOW.app" "$HOME/Applications/KEYFLOW.app"; do
  [ -d "$c" ] || continue
  dup=0
  for a in ${APPS[@]+"${APPS[@]}"}; do [ "$a" = "$c" ] && dup=1; done
  [ $dup -eq 0 ] && APPS+=("$c")
done

if [ $YES -eq 0 ]; then
  confirm "Uninstall KEYFLOW? This removes the app, its preferences and its Input Monitoring permission. Exported WAV files are not touched." || exit 0
fi

# Quit the app if it is running
if pgrep -x "$EXEC_NAME" >/dev/null 2>&1; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  for _ in $(seq 1 30); do pgrep -x "$EXEC_NAME" >/dev/null 2>&1 || break; sleep 0.2; done
  pkill -x "$EXEC_NAME" 2>/dev/null
  sleep 0.5
fi

# Remove the app (ask for admin rights only if needed)
FAILED=0
for app in ${APPS[@]+"${APPS[@]}"}; do
  if ! rm -rf "$app" 2>/dev/null; then
    osascript -e 'on run argv' -e 'do shell script "rm -rf " & quoted form of (item 1 of argv) with administrator privileges' -e 'end run' "$app" >/dev/null 2>&1 || FAILED=1
  fi
  [ -e "$app" ] && FAILED=1
done

# Preferences, caches, saved state, leftover recordings
defaults delete "$BUNDLE_ID" >/dev/null 2>&1
rm -f  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID" \
       "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
       "$HOME/Library/WebKit/$BUNDLE_ID"
rm -f "${TMPDIR:-/tmp}"/KEYFLOW-*.wav 2>/dev/null
killall cfprefsd >/dev/null 2>&1

# Input Monitoring permission entry
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1

if [ $FAILED -eq 0 ]; then
  say "KEYFLOW has been uninstalled."
else
  say "KEYFLOW could not be fully removed. Drag KEYFLOW.app from Applications to the Trash."
  exit 1
fi
"""#
