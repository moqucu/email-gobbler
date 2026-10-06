#!/bin/zsh
# Builds and signs EmailGobbler.app. Pass --install to copy it to /Applications;
# a running copy is quit first and started again afterwards.
set -euo pipefail
root="${0:A:h:h}"
cd "$root/App"

xcodegen generate --quiet
team="${DEVELOPMENT_TEAM:-$(security find-certificate -c "Apple Development" -p \
  | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')}"
[[ -n "$team" ]] || { print -u2 "No Apple Development certificate found; set DEVELOPMENT_TEAM"; exit 1 }

xcodebuild -project EmailGobbler.xcodeproj -scheme EmailGobbler -configuration Release \
  -derivedDataPath build.noindex DEVELOPMENT_TEAM="$team" -quiet build

app="build.noindex/Build/Products/Release/EmailGobbler.app"
codesign --verify --strict --verbose=1 "$app"
codesign --display --entitlements - "$app" 2>/dev/null | grep -q "automation.apple-events" \
  || { print -u2 "Apple Events entitlement missing"; exit 1 }
print "Built $root/App/$app"

if [[ "${1:-}" == "--install" ]]; then
  bundle_id="com.moqucu.EmailGobbler"
  running() { pgrep -f "/Applications/EmailGobbler.app/Contents/MacOS/EmailGobbler" >/dev/null }
  was_running=false
  if running; then
    was_running=true
    # Quit normally so a run in progress finishes; never kill it mid-write.
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null
    for _ in {1..60}; do running || break; sleep 1; done
    running && { print -u2 "EmailGobbler did not quit; quit it from its menu and install again"; exit 1 }
  fi
  ditto "$app" "/Applications/EmailGobbler.app"
  print "Installed /Applications/EmailGobbler.app"
  if $was_running; then
    open "/Applications/EmailGobbler.app"
    print "Restarted EmailGobbler"
  fi
fi
