#!/usr/bin/env bash
# Prints the CI matrix for $GITHUB_OUTPUT: images=[{name,version}], one entry
# per images/<name>/Dockerfile. The published tag is `ARG VERSION=<tag>` when
# the Dockerfile has one, otherwise the tag of its last FROM (an upstream
# image republished under upstream's own tag). A Dockerfile that does not say
# what it publishes fails here, not in a push.
set -euo pipefail
cd "$(dirname "$0")/.."

images='[]'
for f in images/*/Dockerfile; do
  name=$(basename "$(dirname "$f")")
  version=$(sed -n 's/^ARG VERSION=//p' "$f")
  if [[ -z $version ]]; then
    version=$(sed -n 's/^FROM [^[:space:]:@]*:\([^[:space:]@]*\).*/\1/p' "$f" | tail -n 1)
  fi
  [[ $version =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "$f: no tag to publish under (one 'ARG VERSION=<tag>', or a tagged last FROM)" >&2
    exit 1
  }
  images=$(jq -c --arg n "$name" --arg v "$version" '. + [{name: $n, version: $v}]' <<<"$images")
done

echo "images=$images"
