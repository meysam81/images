#!/usr/bin/env bash
# The checks the image build cannot run, because they need Docker.
set -euo pipefail
cd "$(dirname "$0")"

# 1. The upstream tests the build leaves out: they start an Ory Hydra
# container. The source stage is the one the image was just built from (same
# toolchain, same modules); the tests reach Hydra on the host's ports.
docker build -q --target source -t kratos-source . > /dev/null
docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock kratos-source \
  sh -c 'go test -tags sqlite -count=1 -short -run "$NEEDS_DOCKER" ./selfservice/strategy/oidc ./selfservice/strategy/password'

# 2. The image against Postgres. Upstream's tests, here and in the build, run
# on SQLite only, and every rebuild takes the newest pgx: without this, a
# driver that breaks Postgres would be published. The image comes from the
# layers of the build that just ran.
# Keep the major on the one your Kratos database runs.
# renovate: docker=postgres
POSTGRES_VERSION=17.12-alpine@sha256:f9cf3e1f0066f0eb0c48707d864f0ac5941e9ff454a072077d97a4d278d07d73

docker build -q -t kratos-test . > /dev/null
cleanup() {
  docker rm -f kratos-test kratos-test-migrate kratos-test-pg > /dev/null 2>&1 || true
  docker network rm kratos-test > /dev/null 2>&1 || true
  rm -rf "${conf:-}"
}
cleanup
trap cleanup EXIT
conf=$(mktemp -d)
# Made up per run: nothing here is a credential worth keeping in the repo.
pw=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

# shellcheck disable=SC2016 # $id is JSON Schema's, not a shell variable
schema='{"$id":"test","type":"object","properties":{"traits":{"type":"object","required":["email"],"properties":{"email":{"type":"string","format":"email","ory.sh/kratos":{"credentials":{"password":{"identifier":true}}}}}}}}'
cat > "$conf/kratos.yml" << EOF
dsn: postgres://kratos:$pw@kratos-test-pg:5432/kratos?sslmode=disable
identity:
  default_schema_id: test
  schemas:
    - id: test
      url: base64://$(printf '%s' "$schema" | base64 -w0)
secrets:
  default:
    - $pw
selfservice:
  default_browser_return_url: http://127.0.0.1/
  methods:
    password:
      config:
        # No call to api.pwnedpasswords.com from a test.
        haveibeenpwned_enabled: false
EOF
chmod -R a+rX "$conf"

docker network create kratos-test > /dev/null
docker run -d --name kratos-test-pg --network kratos-test \
  -e POSTGRES_USER=kratos -e POSTGRES_PASSWORD="$pw" -e POSTGRES_DB=kratos \
  "postgres:${POSTGRES_VERSION}" > /dev/null
# -h: the socket answers during the init restart, TCP only once it is over.
for _ in $(seq 60); do
  docker exec kratos-test-pg pg_isready -q -h 127.0.0.1 -U kratos && break
  sleep 1
done

# The image's own user, a read-only root and no capabilities.
kratos=(docker run --network kratos-test --read-only --cap-drop ALL -v "$conf:/etc/kratos:ro")
# Kratos retries a database it cannot use forever: the limit turns that into a
# failure.
timeout 120 "${kratos[@]}" --name kratos-test-migrate kratos-test \
  migrate sql -e --yes --config /etc/kratos/kratos.yml > "$conf/migrate.log" 2>&1 || {
  tail -n 5 "$conf/migrate.log" >&2
  exit 1
}
"${kratos[@]}" -d --name kratos-test -p 127.0.0.1::4433 -p 127.0.0.1::4434 \
  kratos-test serve --config /etc/kratos/kratos.yml > /dev/null
# From here on a failure shows what Kratos logged.
trap 'docker logs --tail 40 kratos-test >&2 || true; cleanup' EXIT
public=http://$(docker port kratos-test 4433/tcp)
admin=http://$(docker port kratos-test 4434/tcp)
for _ in $(seq 60); do
  curl -fsS -o /dev/null "$admin/health/ready" 2> /dev/null && break
  sleep 1
done
curl -fsS -o /dev/null "$admin/health/ready"

# Write an identity with a password, then log in with it and read the session
# back: the queries a login runs, through the driver.
json=(-H 'Content-Type: application/json')
login() { jq -n --arg p "$1" '{method: "password", identifier: "test@example.com", password: $p}'; }
id=$(jq -n --arg p "$pw" '{schema_id: "test", traits: {email: "test@example.com"},
  credentials: {password: {config: {password: $p}}}}' |
  curl -fsS "${json[@]}" "$admin/admin/identities" -d @- | jq -er .id)
flow=$(curl -fsS "$public/self-service/login/api" | jq -er .id)
token=$(curl -fsS "${json[@]}" "$public/self-service/login?flow=$flow" \
  -d "$(login "$pw")" | jq -er .session_token)
curl -fsS -H "X-Session-Token: $token" "$public/sessions/whoami" |
  jq -e --arg id "$id" '.active and .identity.id == $id' > /dev/null
# A wrong password must not log in: the login above proves nothing otherwise.
flow=$(curl -fsS "$public/self-service/login/api" | jq -er .id)
status=$(curl -s -o /dev/null -w '%{http_code}' "${json[@]}" "$public/self-service/login?flow=$flow" \
  -d "$(login "not-$pw")")
test "$status" = 400

trap cleanup EXIT
echo "kratos on postgres:${POSTGRES_VERSION%%@*}: migrate, serve, login ok"
