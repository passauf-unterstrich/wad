#!/bin/zsh
# make-dmg.sh
# Baut die Version zum Weitergeben: Wad.app als Universal-App, signiert mit dem Zertifikat
# „Developer ID Application“, verpackt in eine DMG und von Apple notarisiert. Ergebnis: build/dist/
#
# Einmalig vorher: Zugang für die Notarisierung im Schlüsselbund hinterlegen. Der Befehl fragt
# Apple-ID, Team-ID und ein App-spezifisches Passwort ab (erstellt unter account.apple.com):
#   xcrun notarytool store-credentials wad-notary
#
# Ohne Notarisierung, nur zum Ausprobieren:  NOTARIZE=0 ./Scripts/make-dmg.sh

set -euo pipefail
cd "${0:A:h}/.."

identity="${SIGN_IDENTITY:-Developer ID Application}"
notary_profile="${NOTARY_PROFILE:-wad-notary}"

echo "▸ Baue Wad (Release, Apple-Chip und Intel), signiert mit „$identity“"
xcodebuild -project Wad.xcodeproj -scheme Wad -configuration Release -derivedDataPath build \
    CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build | grep -E "error|BUILD"

app=build/Build/Products/Release/Wad.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
codesign --verify --deep --strict "$app"

echo "▸ Verpacke Wad $version in eine DMG"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Programme"
mkdir -p build/dist
dmg="build/dist/Wad-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "Wad" -srcfolder "$staging" -format UDZO -quiet "$dmg"
codesign --sign "$identity" --timestamp "$dmg"

if [[ "${NOTARIZE:-1}" == "1" ]]; then
    echo "▸ Lasse die DMG von Apple notarisieren (dauert meist wenige Minuten)"
    xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi

echo "✓ Fertig: $dmg"
shasum -a 256 "$dmg"
