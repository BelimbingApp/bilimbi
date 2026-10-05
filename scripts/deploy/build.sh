#!/usr/bin/env bash
set -euo pipefail

version=${1:?usage: build.sh VERSION (letters, numbers, dots, underscores, hyphens)}
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Invalid version" >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
mkdir -p "$root/dist"
docker build --platform linux/amd64 --file "$root/scripts/deploy/Dockerfile.ubuntu-26.04" \
  --build-arg "RELEASE_VERSION=$version" --tag "bilimbi-build:$version" "$root"
container=$(docker create "bilimbi-build:$version")
trap 'docker rm -f "$container" >/dev/null' EXIT
docker cp "$container:/out/bilimbi-$version-ubuntu-26.04-amd64.tar.gz" "$root/dist/"
(cd "$root/dist" && sha256sum "bilimbi-$version-ubuntu-26.04-amd64.tar.gz" > "bilimbi-$version-ubuntu-26.04-amd64.tar.gz.sha256")
