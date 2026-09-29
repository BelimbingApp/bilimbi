#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
days=${1:-14}
if ! [[ "$days" =~ ^[0-9]+$ ]] || ((days < 1)); then
  echo "Retention must be at least one day" >&2; exit 2
fi
dir=/var/backups/bilimbi
install -d -o postgres -g postgres -m 0700 "$dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
partial="$dir/bilimbi-$stamp.dump.partial"
final="$dir/bilimbi-$stamp.dump"
trap 'rm -f -- "$partial"' EXIT
runuser -u postgres -- pg_dump --format=custom --file="$partial" bilimbi
mv -- "$partial" "$final"
trap - EXIT
find "$dir" -maxdepth 1 -type f -name 'bilimbi-*.dump' -mtime "+$((days - 1))" -delete
echo "$final"
