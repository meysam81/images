# Ory Kratos with SQLite, on a supported Alpine. Upstream's SQLite-capable
# image sits on an end-of-life Alpine and its distroless one leaves SQLite
# out. The binary is upstream's, unchanged: it links only against musl.
FROM oryd/kratos:v26.2.0@sha256:2a13bb8d362c7a7ae33bd7c0f5168aee46921f15c916a06346db91c06dc76643 AS upstream

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

# image-version: docker=oryd/kratos
ARG VERSION=v26.2.0

# A failing command before a pipe must fail the build. Never `grep -q` under
# pipefail: it exits at the first match and the writer dies of SIGPIPE.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

# Same user, group and directories as upstream, so volumes keep their owner.
# hadolint ignore=DL3018
RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates \
    && addgroup -S -g 101 ory \
    && adduser -S -D -H -u 10000 -G ory -h /home/ory -s /sbin/nologin ory \
    && install -d -o ory -g ory /home/ory /var/lib/sqlite

COPY --from=upstream /usr/bin/kratos /usr/bin/kratos

# The published tag is the version the binary reports.
RUN kratos version 2>&1 | grep "${VERSION}" > /dev/null

USER 10000
WORKDIR /home/ory
EXPOSE 4433 4434
ENTRYPOINT ["kratos"]
CMD ["serve"]
