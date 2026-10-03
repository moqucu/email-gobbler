#!/bin/zsh
# Builds and signs MailToNumbers.app. Pass --install to copy it to /Applications.
set -euo pipefail
root="${0:A:h:h}"
cd "$root/App"

xcodegen generate --quiet
team="${DEVELOPMENT_TEAM:-$(security find-certificate -c "Apple Development" -p \
  | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')}"
[[ -n "$team" ]] || { print -u2 "No Apple Development certificate found; set DEVELOPMENT_TEAM"; exit 1 }

xcodebuild -project MailToNumbers.xcodeproj -scheme MailToNumbersApp -configuration Release \
  -derivedDataPath build DEVELOPMENT_TEAM="$team" -quiet build

app="build/Build/Products/Release/MailToNumbers.app"
codesign --verify --strict --verbose=1 "$app"
codesign --display --entitlements - "$app" 2>/dev/null | grep -q "automation.apple-events" \
  || { print -u2 "Apple Events entitlement missing"; exit 1 }
print "Built $root/App/$app"

if [[ "${1:-}" == "--install" ]]; then
  ditto "$app" /Applications/MailToNumbers.app
  print "Installed /Applications/MailToNumbers.app"
fi
