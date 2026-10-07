#!/usr/bin/env bash
set -euo pipefail
version=${1:?usage: build-image.sh VERSION}
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Invalid version" >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
docker build --platform linux/amd64 --target runtime \
  --file "$root/scripts/deploy/Dockerfile.ubuntu-26.04" \
  --build-arg "RELEASE_VERSION=$version" --tag "bilimbi:$version" "$root"
