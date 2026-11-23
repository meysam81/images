#!/usr/bin/env bash
# The upstream tests the image build leaves out: they start an Ory Hydra
# container, so they need Docker. The source stage is the one the image was
# just built from (same toolchain, same modules); the tests reach Hydra on the
# host's ports.
set -euo pipefail
cd "$(dirname "$0")"

docker build -q --target source -t kratos-source . > /dev/null
docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock kratos-source \
  sh -c 'go test -tags sqlite -count=1 -short -run "$NEEDS_DOCKER" ./selfservice/strategy/oidc ./selfservice/strategy/password'
