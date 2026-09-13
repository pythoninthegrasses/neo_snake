# syntax=docker/dockerfile:1.17.1
# check=skip=all

FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS deps

RUN true <<'DOCKERFILE'
Multi-stage Dockerfile for Linux x86_64 builds (TASK-045), mirroring
~/git/mt/docker/linux/Dockerfile's stage shape. Settles the glibc-baseline
question by construction: every toolchain download is checksum-verified
and pinned to this repo's own .tool-versions, and the GDExtension is built
against an explicit glibc floor (x86_64-linux-gnu.2.28) matched to Godot's
own shipped linux_release.x86_64 export template (see
docs/build-layout.md's TASK-045 section for how that floor was measured).

Stages:
  deps      - system packages, Zig, go-task, uv, scons (pinned + checksummed)
  src       - repo source copied in
  check     - Tier-A/B/C (core:test, core:difftest, core:abitest)
  build     - the GDExtension shared library, glibc floor pinned
  artifacts - extract the built .so

Usage:
  docker build --target check .
  docker build --target artifacts --output type=local,dest=dist .
DOCKERFILE

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    xz-utils \
    pipx \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Pinned to .tool-versions' `zig` entry. Verified against ziglang.org/download/index.json.
ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
    && echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - \
    && mkdir -p /usr/local/zig \
    && tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz
ENV PATH="/usr/local/zig:${PATH}"

# Pinned to .tool-versions' `task` entry. Verified against the release's
# own task_checksums.txt.
ARG TASK_VERSION=3.49.1
ARG TASK_SHA256=4e7d24f1bf38218aec8f244eb7ba671f898830f9f87b3c9b30ff1c09e3135576
RUN curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz" -o /tmp/task.tar.gz \
    && echo "${TASK_SHA256}  /tmp/task.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/task.tar.gz -C /usr/local/bin task \
    && rm /tmp/task.tar.gz

# Pinned to .tool-versions' `uv` entry. Verified against the release's own
# uv-x86_64-unknown-linux-gnu.tar.gz.sha256. Needed at runtime: the abi-header
# and abi-test purity checks (tools/validate_*.py) shebang `uv run --script`.
ARG UV_VERSION=0.11.26
ARG UV_SHA256=6426a73c3837e6e2483ee344cbc00f36394d179afcba6183cb77437e67db4af0
RUN curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/uv.tar.gz \
    && echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/uv.tar.gz -C /tmp \
    && mv /tmp/uv-x86_64-unknown-linux-gnu/uv /tmp/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/ \
    && rm -rf /tmp/uv.tar.gz /tmp/uv-x86_64-unknown-linux-gnu

# Pinned to .tool-versions' `pipx:scons` entry (pipx, not apt, matching how
# this repo's own mise config installs it).
ARG SCONS_VERSION=4.11.1
ENV PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin
RUN pipx install "scons==${SCONS_VERSION}"

ENV TASK_X_ENV_PRECEDENCE=1
WORKDIR /build

FROM deps AS src

COPY . .

FROM src AS check

RUN task core:test core:difftest core:abitest

FROM src AS build

# Matches docs/build-layout.md's TASK-045 section: the highest GLIBC_x.y
# symbol version referenced by Godot's own shipped linux_release.x86_64
# export template (measured via objdump -T against the 4.7.1-stable export
# templates archive) is GLIBC_2.28 -- pinning the same floor here means the
# GDExtension never requires a newer glibc than the engine itself already
# does, regardless of whatever glibc the container's own base image ships.
ARG GDEXTENSION_GLIBC_TARGET=x86_64-linux-gnu.2.28
RUN task extension:build ZIG_TARGET_FLAG="-Dtarget=${GDEXTENSION_GLIBC_TARGET}"

FROM scratch AS artifacts

COPY --from=build /build/game/bin/libneo_snake.linux.template_debug.x86_64.so /
