# Ory Kratos, compiled from upstream's release source with a current Go
# toolchain and current versions of the modules that carry its security
# fixes. Upstream's own binary is rebuilt only when Ory cuts a release, so it
# keeps the Go version and the modules of its release day. The source is not
# patched: upstream's unit tests run against the bumped modules and gate the
# build. SQLite is compiled in, so this runs both a SQLite and a Postgres
# instance.

# The upstream release this is compiled from, and the tag it is published
# under. A tag can be moved: the commit is what is built.
# image-version: github-tags=ory/kratos
ARG VERSION=v26.2.0
ARG COMMIT=9d7085948039ffb8960160d4979f71527b5cf4d5

# Cross-compiles for the target platform, cgo included: nothing below runs
# emulated except the final version check.
FROM --platform=$BUILDPLATFORM tonistiigi/xx:1.10.0@sha256:40fe21f44bb8cddf1eb1226db190d0a984118f62ee02a91b77d99448d28264a6 AS xx

FROM --platform=$BUILDPLATFORM golang:1.27.4-alpine3.24@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280 AS source

# A failing command before a pipe must fail the build. Never `grep -q` under
# pipefail: it exits at the first match and the writer dies of SIGPIPE.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

# xx is a scratch image of its own scripts, made to be copied whole.
# hadolint ignore=DL3067
COPY --from=xx / /

# hadolint ignore=DL3018
RUN apk add --no-cache build-base clang git lld

ARG VERSION
ARG COMMIT

WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/ory/kratos.git \
    && git fetch -q --depth 1 origin "refs/tags/${VERSION}" \
    && test "$(git rev-parse 'FETCH_HEAD^{commit}')" = "${COMMIT}" \
    && git checkout -q FETCH_HEAD

ENV CGO_ENABLED=1 \
    CGO_CPPFLAGS=-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600 \
    GOFLAGS=-mod=mod \
    GOTOOLCHAIN=local

# The modules below are the ones Kratos' security findings come from. Each
# moves to its latest release on every rebuild, which is how their fixes
# arrive between Ory's releases. A release that no longer compiles or fails
# the tests stops the build, and the last published image stays.
# hadolint ignore=DL3062
RUN go get \
        github.com/go-jose/go-jose/v3@latest \
        github.com/go-jose/go-jose/v4@latest \
        github.com/jackc/pgx/v5@latest \
        go.opentelemetry.io/otel/sdk@latest \
        go.opentelemetry.io/otel@latest \
        golang.org/x/crypto@latest \
        golang.org/x/mod@latest \
        golang.org/x/net@latest \
        google.golang.org/grpc@latest \
    && go mod tidy

# Five of upstream's tests start an Ory Hydra container, which an image build
# cannot do: test.sh runs exactly those, with Docker, before anything is
# published. A new upstream test of that kind fails here by name.
ENV NEEDS_DOCKER='^(TestOAuth2Provider|TestOAuth2ProviderRegistration|TestPostEndpointRedirect|TestSettingsStrategy|TestStrategy)$'

# Upstream's `make test-short`, on the build machine's own architecture: every
# package in full, except that the two with Hydra tests leave those out.
FROM source AS test
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
# A failing `go list` or an empty package list fails the pipe, so "no
# packages" can never pass as "no failures".
RUN go list ./... > /tmp/packages \
    && grep -v -E '/selfservice/strategy/(oidc|password)$' /tmp/packages \
        | xargs go test -tags sqlite -count=1 -short \
    && go test -tags sqlite -count=1 -short -skip "${NEEDS_DOCKER}" \
        ./selfservice/strategy/oidc ./selfservice/strategy/password \
    && touch /tested

FROM source AS build
ARG TARGETPLATFORM
# hadolint ignore=DL3018
RUN xx-apk add --no-cache gcc musl-dev
# The file from the test stage is what makes the tests a gate: BuildKit skips
# a stage nothing depends on.
COPY --from=test /tested /tested
RUN xx-go build -tags sqlite \
        -ldflags="-s -w -X github.com/ory/kratos/driver/config.Version=${VERSION} -X github.com/ory/kratos/driver/config.Commit=${COMMIT}" \
        -o /kratos . \
    && xx-verify /kratos

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ARG VERSION

# Same user, group and directories as upstream's image, so volumes keep
# their owner.
# hadolint ignore=DL3018
RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates \
    && addgroup -S -g 101 ory \
    && adduser -S -D -H -u 10000 -G ory -h /home/ory -s /sbin/nologin ory \
    && install -d -o ory -g ory /home/ory /var/lib/sqlite

COPY --from=build /kratos /usr/bin/kratos

RUN kratos version 2>&1 | grep "${VERSION}" > /dev/null

USER 10000
WORKDIR /home/ory
EXPOSE 4433 4434
ENTRYPOINT ["kratos"]
CMD ["serve"]
