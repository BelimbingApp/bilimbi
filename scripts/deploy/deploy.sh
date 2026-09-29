#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo on the server" >&2; exit 1; }
archive=${1:?usage: sudo deploy.sh /path/to/tarball VERSION [KEEP_COUNT]}
version=${2:?usage: sudo deploy.sh /path/to/tarball VERSION [KEEP_COUNT]}
keep=${3:-5}
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Invalid version" >&2; exit 2; }
if ! [[ "$keep" =~ ^[0-9]+$ ]] || ((keep < 2)); then
  echo "KEEP_COUNT must be at least 2" >&2; exit 2
fi
[[ -f "$archive" && -f "$archive.sha256" ]] || { echo "Tarball and .sha256 required" >&2; exit 2; }
[[ -f /etc/bilimbi/bilimbi.env ]] || { echo "Missing /etc/bilimbi/bilimbi.env" >&2; exit 2; }
expected="bilimbi-$version-ubuntu-24.04-amd64.tar.gz"
[[ "$(basename -- "$archive")" == "$expected" ]] || { echo "Tarball name/version mismatch" >&2; exit 2; }
(cd -- "$(dirname -- "$archive")" && sha256sum -c -- "$(basename -- "$archive").sha256")

root=/opt/bilimbi
releases=$root/releases
target=$releases/$version
current=$root/current
previous=$(readlink -f "$current" 2>/dev/null || true)
if [[ -n "$previous" && "$previous" == "$target" ]]; then
  echo "Version $version is already current"
  exit 0
fi
if [[ -e "$target" ]]; then
  if [[ ! -f "$target/.archive.sha256" ]] || \
     ! cmp -s "$target/.archive.sha256" <(sha256sum "$archive" | cut -d' ' -f1); then
    echo "Version exists with different or unknown archive" >&2
    exit 1
  fi
else
  staging=$(mktemp -d "$releases/.deploy.XXXXXXXX")
  trap 'rm -rf -- "${staging:-}"' EXIT
  tar -xzf "$archive" -C "$staging"
  [[ -x "$staging/bilimbi/bin/bilimbi" ]] || { echo "Not a Bilimbi release" >&2; exit 1; }
  mv -- "$staging/bilimbi" "$target"
  rmdir "$staging"
  staging=
  sha256sum "$archive" | cut -d' ' -f1 > "$target/.archive.sha256"
  chown -R root:bilimbi "$target"
fi

# EnvironmentFile is read by systemd, but the one-off migration needs the same
# bootstrap configuration. This file is installed by root and is never logged.
set -a
# shellcheck disable=SC1091
source /etc/bilimbi/bilimbi.env
set +a
unset PHX_SERVER
runuser -u bilimbi -- "$target/bin/bilimbi" eval 'BilimbiWeb.Release.migrate()'

ln -sfn "$target" "$root/.current.next"
mv -Tf "$root/.current.next" "$current"
systemctl restart bilimbi || true
healthy=false
for _ in $(seq 1 30); do
  if curl --silent --fail --output /dev/null --max-time 2 \
      --header 'Host: localhost' "http://127.0.0.1:${PORT:-4000}/"; then
    healthy=true
    break
  fi
  sleep 2
done
if [[ "$healthy" != true ]]; then
  echo "Health check failed; restoring previous release" >&2
  if [[ -n "$previous" && -d "$previous" ]]; then
    ln -sfn "$previous" "$root/.current.next"
    mv -Tf "$root/.current.next" "$current"
    systemctl restart bilimbi
  else
    systemctl stop bilimbi
    rm -f "$current"
  fi
  exit 1
fi

# Keep the current and previous release even if they fall outside the newest N.
mapfile -t old < <(find "$releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | tail -n "+$((keep + 1))" | cut -d' ' -f2-)
for path in "${old[@]}"; do
  [[ "$path" == "$target" || "$path" == "$previous" ]] || rm -rf -- "$path"
done
echo "Bilimbi $version healthy"
