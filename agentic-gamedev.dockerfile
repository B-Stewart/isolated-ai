# syntax=docker/dockerfile:1.7
FROM braydens/agentic-base:latest

ARG TARGETARCH
ARG GODOT_VERSION=4.7.2-stable
ARG BLENDER_VERSION=5.2.2
ARG BLENDER_SHA256=84098912789dc450e95697c4184fb8a90acbe5111c2ba4aede3fecb57806a168
ARG DOTNET_RUNTIME_VERSION=8.0

# Blender's official Linux archive is x64; this image currently targets amd64.
RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) ;; \
        *) echo "ERROR: agentic-gamedev currently supports linux/amd64 only (got ${TARGETARCH:-$(dpkg --print-architecture)})" >&2; exit 1 ;; \
    esac

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        xz-utils \
        dotnet-runtime-${DOTNET_RUNTIME_VERSION} \
        libfontconfig1 \
        libfreetype6 \
        libgl1 \
        libice6 \
        libsm6 \
        libxinerama1 \
        libxcursor1 \
        libxi6 \
        libxfixes3 \
        libxrender1 \
        libxrandr2 \
        libxkbcommon0 \
        libwayland-client0 \
        libwayland-cursor0 \
        libwayland-egl1 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    godot_archive="Godot_v${GODOT_VERSION}_mono_linux_x86_64.zip"; \
    curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/SHA512-SUMS.txt" -o /tmp/godot-sha512sums.txt; \
    godot_checksum="$(awk -v name="${godot_archive}" '$2 == name || $2 == "*" name { print $1 }' /tmp/godot-sha512sums.txt)"; \
    test "$(printf '%s\n' "$godot_checksum" | wc -l)" -eq 1; \
    test "${#godot_checksum}" -eq 128; \
    curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${godot_archive}" -o /tmp/godot.zip; \
    printf '%s  %s\n' "$godot_checksum" /tmp/godot.zip | sha512sum --check --status; \
    mkdir -p /opt/godot; \
    unzip -q /tmp/godot.zip -d /opt/godot; \
    godot_binary="$(find /opt/godot -type f -name 'Godot_v*_mono_linux.x86_64' -print -quit)"; \
    test -n "$godot_binary"; \
    chmod 0755 "$godot_binary"; \
    ln -s "$godot_binary" /usr/local/bin/godot; \
    rm -f /tmp/godot.zip /tmp/godot-sha512sums.txt

RUN set -eux; \
    blender_archive="blender-${BLENDER_VERSION}-linux-x64.tar.xz"; \
    blender_series="Blender${BLENDER_VERSION%.*}"; \
    curl -fsSL "https://mirrors.iu13.net/blender/release/${blender_series}/${blender_archive}" -o /tmp/blender.tar.xz; \
    printf '%s  %s\n' "${BLENDER_SHA256}" /tmp/blender.tar.xz | sha256sum --check --status; \
    mkdir -p /opt/blender; \
    tar -xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender; \
    test -x /opt/blender/blender; \
    ln -s /opt/blender/blender /usr/local/bin/blender; \
    rm -f /tmp/blender.tar.xz

USER agent
WORKDIR /workspace
