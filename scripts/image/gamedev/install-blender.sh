#!/usr/bin/env bash
set -euo pipefail

# Pass the configured Blender version and SHA-256 checksum as the first two arguments.
blender_version="${1:?usage: install-blender.sh BLENDER_VERSION BLENDER_SHA256}"
blender_sha256="${2:?usage: install-blender.sh BLENDER_VERSION BLENDER_SHA256}"

set -x
blender_archive="blender-${blender_version}-linux-x64.tar.xz"
blender_series="Blender${blender_version%.*}"
curl -fsSL "https://mirrors.iu13.net/blender/release/${blender_series}/${blender_archive}" -o /tmp/blender.tar.xz
printf '%s  %s\n' "${blender_sha256}" /tmp/blender.tar.xz | sha256sum --check --status
mkdir -p /opt/blender
tar -xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender
test -x /opt/blender/blender
ln -s /opt/blender/blender /usr/local/bin/blender
rm -f /tmp/blender.tar.xz
