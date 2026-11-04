#!/bin/bash
# Stops Daywall and removes the LaunchAgent and its data folder (including any saved calendar URL).
launchctl bootout "gui/$(id -u)/com.user.daywall" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.user.daywall.plist"
rm -rf "$HOME/Library/Application Support/Daywall"
open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
echo "Daywall removed. Pick a new wallpaper in the System Settings window that just opened."
