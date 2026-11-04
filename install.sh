#!/bin/bash
# Builds Daywall and installs a LaunchAgent that refreshes the wallpaper every 15 minutes
# (it only re-renders when something changed).
#
# Optional settings, passed as environment variables:
#   DAYWALL_LOCATION="Oslo"                          weather location (default: locate by IP)
#   DAYWALL_ICS="https://…/calendar.ics"             calendar feed for the week agenda
#   DAYWALL_TICKERS="Bitcoin=BTC-USD,Nasdaq 100=^NDX" market quotes (Yahoo Finance symbols)
#   DAYWALL_HERO="digit"                             digit | daylight | moon | next | year
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/Library/Application Support/Daywall"
LABEL="com.user.daywall"
PL="$HOME/Library/LaunchAgents/$LABEL.plist"

command -v swiftc >/dev/null || { echo "swiftc not found. Install the Xcode Command Line Tools: xcode-select --install"; exit 1; }

mkdir -p "$DIR" "$HOME/Library/LaunchAgents"
echo "Compiling…"
swiftc -O "$SRC/daywall.swift" -o "$DIR/daywall"

if [ -n "${DAYWALL_ICS:-}" ]; then
  (umask 077; printf '%s\n' "$DAYWALL_ICS" > "$DIR/calendar-url")
  echo "Saved calendar URL to $DIR/calendar-url (readable only by you)."
fi

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
ENV=""
for v in DAYWALL_LOCATION DAYWALL_TICKERS DAYWALL_HERO; do
  if [ -n "${!v:-}" ]; then ENV+="    <key>$v</key><string>$(xml "${!v}")</string>"$'\n'; fi
done

cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/daywall</string></array>
  <key>EnvironmentVariables</key>
  <dict>
$ENV  </dict>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>900</integer>
  <key>StandardErrorPath</key><string>$DIR/daywall.log</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST
plutil -lint -s "$PL"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PL"
echo "Daywall installed — your wallpaper will update in a few seconds."
echo "Log: $DIR/daywall.log   Uninstall: $SRC/uninstall.sh"
