# rsync and nothing else: no curl and no ssh client, so none of their
# libraries either.
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

# The published tag: rsync's minor version, so a patch release (how Alpine
# ships a security fix inside a branch) needs no change here.
ARG VERSION=3.5

# A failing command before a pipe must fail the build. Never `grep -q` under
# pipefail: it exits at the first match and the writer dies of SIGPIPE.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

# Unpinned on purpose: the weekly rebuild is how security fixes arrive. The
# check only fails when rsync's minor version moves, which is a new Alpine
# branch: the pull request that bumps FROM is where VERSION follows.
# hadolint ignore=DL3018
RUN apk upgrade --no-cache \
    && apk add --no-cache rsync \
    && rsync --version | grep "version ${VERSION}\\." > /dev/null

USER 65534:65534
ENTRYPOINT ["rsync"]
