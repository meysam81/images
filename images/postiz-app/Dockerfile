# Postiz as upstream ships it, with its Debian packages upgraded: upstream
# installs them once per release and never upgrades the base it builds on.
# No ARG VERSION: this publishes under upstream's own tag.
FROM ghcr.io/gitroomhq/postiz-app:v2.26.0@sha256:875e61ac5d0ac43c3dec78a78a7032dfb03d9a8c6d4936ebb18adb606cc207c5

# Upstream runs as root and so does this layer; the user is left as it was.
# hadolint ignore=DL3005
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*
