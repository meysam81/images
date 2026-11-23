# images

Container images we publish because upstream's are not good enough to run:
either the software has no small image of its own, or upstream's image sits on
a base that is stale or end of life. Nothing here changes an upstream
program's code. A change to the code belongs in a fork of that project.

Every image is rebuilt from scratch and republished every Sunday night, and on
every push to `main`. The rebuild is the patch: it reruns the OS package
upgrade, so a fix the distribution has shipped lands within a week without
anyone touching this repo. For a fix that cannot wait, run the `ci` workflow
by hand.

| Image                                | What it is                                                     |
| ------------------------------------ | -------------------------------------------------------------- |
| `ghcr.io/meysam81/images/rsync`      | rsync on Alpine and nothing else: no curl, no ssh client       |
| `ghcr.io/meysam81/images/kratos`     | Ory Kratos' own binary with SQLite, on a supported Alpine      |
| `ghcr.io/meysam81/images/postiz-app` | Postiz as upstream ships it, with its Debian packages upgraded |

`postiz-app` redistributes [Postiz](https://github.com/gitroomhq/postiz-app)
(AGPL-3.0) unchanged apart from its OS packages; its source is upstream's, at
the tag the image carries.

## Using one

Images are public and need no token. A tag moves with each rebuild, so pin the
digest beside it and let Renovate propose the next one:

```yaml
image: ghcr.io/meysam81/images/rsync:3.5@sha256:<digest>
```

Each one is signed by this repo's workflow and carries an SBOM and SLSA
provenance:

```sh
cosign verify ghcr.io/meysam81/images/rsync:3.5 \
  --certificate-identity-regexp '^https://github.com/meysam81/images/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Adding one

One directory, one file: `images/<name>/Dockerfile`. CI finds it by itself.

- Pin every `FROM` by digest. Renovate moves the pins.
- Upgrade the OS packages in the same layer that installs anything
  (`apk upgrade --no-cache`, `apt-get update && apt-get upgrade -y`), and do
  not pin package versions: the weekly rebuild is how fixes arrive.
- Say which tag it publishes under:
  - An upstream image with patched packages publishes under upstream's own
    tag: the tag of the last `FROM`. Add nothing (see `postiz-app`).
  - Anything else declares `ARG VERSION=<tag>` and a `RUN` that fails the
    build when the software reports another version. Pick a tag the weekly
    rebuild cannot outrun: `rsync` publishes under its minor version, so a
    patch release needs no change. Where the tag follows an upstream image,
    put `# image-version: docker=<image>` on the line above and Renovate moves
    it together with the `FROM` (see `kratos`).
- After its first publish, make the package public once: GitHub creates every
  package private. Package settings, Danger Zone, Change visibility. This
  cannot be undone.

## What CI checks

- A pull request builds every image and fails if an OS package is missing a
  high or critical fix that exists. That is the part this repo controls. What
  an upstream binary compiles in (a Go module, a bundled tool) is not gated:
  only upstream, or a fork that rebuilds from source, can fix it.
- `main`, the weekly schedule and manual runs do the same, then publish for
  `linux/amd64` and `linux/arm64`, sign with cosign and attach the SBOM and
  provenance.
- Every run scans for secrets (gitleaks) and lints the workflows (actionlint,
  zizmor) and the Dockerfiles (hadolint).

## Working here

```sh
pre-commit install --install-hooks -t pre-commit -t commit-msg
./scripts/matrix.sh   # what CI would build, and under which tag
docker build images/rsync
```
