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
    --mount=type=bind,source=scripts/image/gamedev/install-system-deps.sh,target=/tmp/install-system-deps.sh,ro \
    bash /tmp/install-system-deps.sh "${DOTNET_RUNTIME_VERSION}"

RUN --mount=type=bind,source=scripts/image/gamedev/install-godot.sh,target=/tmp/install-godot.sh,ro \
    bash /tmp/install-godot.sh "${GODOT_VERSION}"

RUN --mount=type=bind,source=scripts/image/gamedev/install-blender.sh,target=/tmp/install-blender.sh,ro \
    bash /tmp/install-blender.sh "${BLENDER_VERSION}" "${BLENDER_SHA256}"

USER agent
WORKDIR /workspace
