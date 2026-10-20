#!/usr/bin/env bash
set -euo pipefail

# Pass the configured Godot release version as the first argument.
godot_version="${1:?usage: install-godot.sh GODOT_VERSION}"

set -x
godot_archive="Godot_v${godot_version}_mono_linux_x86_64.zip"
curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${godot_version}/SHA512-SUMS.txt" -o /tmp/godot-sha512sums.txt
godot_checksum="$(awk -v name="${godot_archive}" '$2 == name || $2 == "*" name { print $1 }' /tmp/godot-sha512sums.txt)"
test "$(printf '%s\n' "$godot_checksum" | wc -l)" -eq 1
test "${#godot_checksum}" -eq 128
curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${godot_version}/${godot_archive}" -o /tmp/godot.zip
printf '%s  %s\n' "$godot_checksum" /tmp/godot.zip | sha512sum --check --status
mkdir -p /opt/godot
unzip -q /tmp/godot.zip -d /opt/godot
godot_binary="$(find /opt/godot -type f -name 'Godot_v*_mono_linux.x86_64' -print -quit)"
test -n "$godot_binary"
chmod 0755 "$godot_binary"
ln -s "$godot_binary" /usr/local/bin/godot
rm -f /tmp/godot.zip /tmp/godot-sha512sums.txt
