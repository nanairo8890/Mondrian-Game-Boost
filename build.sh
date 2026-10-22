#!/bin/bash
# Builds Mondrian-Game-Boost: the root module that gives the power HAL of Project Infinity-X 4.1 /
# MistOS 5.1 for mondrian actions for Android's GAME and GAME_LOADING modes (injected by NoMount over
# /vendor/etc/powerhint.json), plus MistOS's ART settings.
#
#   ./build.sh
#
# Source: module/, base powerhint.json in ref/. Output: out/Mondrian-Game-Boost-<version>.zip
# Needs python3, zip and sha256sum.
set -euo pipefail
cd "$(dirname "$0")"

BASE=ref/powerhint-infinityx-20261017.json
VERSION=v1.0
VERSIONCODE=100
ZIP=$PWD/out/Mondrian-Game-Boost-$VERSION.zip

ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT
cp -a module/. "$ST/"
sed -i -e "s/@VERSION@/$VERSION/" -e "s/@VERSIONCODE@/$VERSIONCODE/" "$ST/module.prop"
sed -i "s/@BASE_SHA@/$(sha256sum "$BASE" | cut -d' ' -f1)/" "$ST/common.sh"

python3 tools/gen_powerhint.py "$BASE" "$ST" "$VERSION"
# The file NoMount injects (post-fs-data.sh puts the chosen level's there each boot) and the ROM's,
# which the scripts give back to the power HAL if it rejects the module's
mkdir -p "$ST/system/vendor/etc"
cp "$ST/powerhint-alto.json" "$ST/system/vendor/etc/powerhint.json"
cp "$BASE" "$ST/powerhint-rom.json"

# The scripts run under busybox ash: LF only and POSIX sh syntax; no placeholders left
if grep -rlI $'\r' "$ST"; then echo "[!] CRLF in the files above"; exit 1; fi
if grep -rl '@[A-Z_]*@' "$ST"; then echo "[!] placeholder left in the files above"; exit 1; fi
for s in "$ST"/*.sh "$ST/META-INF/com/google/android/update-binary"; do sh -n "$s"; done
if grep -vE '^[a-z0-9._-]+=[^ ]+$' "$ST/system.prop"; then echo "[!] bad line in system.prop"; exit 1; fi

mkdir -p out
rm -f "$ZIP"
(cd "$ST" && zip -qr9 -X "$ZIP" META-INF module.prop customize.sh common.sh post-fs-data.sh \
  post-mount.sh service.sh action.sh webui.sh system.prop sepolicy.rule powerhint-alto.json \
  powerhint-maximo.json powerhint-rom.json system webroot README.md)
unzip -l "$ZIP" | tail -n +4 | head -n -2
sha256sum "$ZIP"
