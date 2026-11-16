#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/drive.sh start [file-or-link]   launch a muted background copy of build/Flick.app
       scripts/drive.sh shot <out.png>         screenshot its window, scaled to fit 1400 px
       scripts/drive.sh stop                   quit it and remove its data

The copy is FlickDrive.app (bundle id dev.flick.drive): it never takes focus,
plays no sound, and keeps its library, resume points and settings in
$FLICK_DRIVE_ROOT (default $TMPDIR/flick-drive), apart from the real Flick.
Drive its UI with agent-desktop: agent-desktop snapshot --app FlickDrive
USAGE
}

repo="$(cd "$(dirname "$0")/.." && pwd)"
root="${FLICK_DRIVE_ROOT:-${TMPDIR:-/tmp}/flick-drive}"
app="$root/FlickDrive.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

window_id() {
  swift "$repo/scripts/window-id.swift" FlickDrive
}

stop() {
  pkill -x FlickDrive 2>/dev/null || true
  for _ in $(seq 50); do pgrep -x FlickDrive >/dev/null || break; sleep 0.1; done
  [[ -d "$app" ]] && "$lsregister" -u "$app" 2>/dev/null || true
  rm -rf "$root"
}

make_copy() {
  [[ -d "$repo/build/Flick.app" ]] || { echo "build/Flick.app is missing: run make app" >&2; exit 1; }
  mkdir -p "$root/data"
  cp -R "$repo/build/Flick.app" "$app"
  mv "$app/Contents/MacOS/Flick" "$app/Contents/MacOS/FlickDrive"
  local plist="$app/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string dev.flick.drive "$plist"
  plutil -replace CFBundleName -string FlickDrive "$plist"
  plutil -replace CFBundleDisplayName -string FlickDrive "$plist"
  plutil -replace CFBundleExecutable -string FlickDrive "$plist"
  plutil -replace SUEnableAutomaticChecks -bool NO "$plist"
  plutil -remove CFBundleDocumentTypes "$plist"
  codesign --force --sign - "$app" 2>/dev/null
}

start() {
  stop
  make_copy
  open -g -n -a "$app" --env "FLICK_DRIVE_DIR=$root/data" "$@"
  for _ in $(seq 100); do
    if id=$(window_id 2>/dev/null); then
      echo "FlickDrive running: pid $(pgrep -x FlickDrive) window $id"
      return
    fi
    sleep 0.2
  done
  echo "FlickDrive showed no window within 20s" >&2
  exit 1
}

shot() {
  local out="$1" id
  id=$(window_id) || { echo "no FlickDrive window: run start first" >&2; exit 1; }
  screencapture -x -o -l "$id" "$out"
  sips -Z 1400 "$out" >/dev/null
  echo "$out"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  shot) [[ $# -eq 2 ]] || { usage; exit 2; }; shot "$2" ;;
  stop) stop; echo "FlickDrive stopped" ;;
  *) usage; exit 2 ;;
esac
