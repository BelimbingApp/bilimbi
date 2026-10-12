#!/usr/bin/env bash
# Privileged installation is separate from mkcert so it uses the developer's
# existing CA, not root's CA. Preserve and reload the shared Caddy service.
set -euo pipefail
[[ $EUID -eq 0 && $# -eq 5 ]] || { echo "Internal helper: call scripts/local-https.sh" >&2; exit 1; }
root=$1 host=$2 port=$3 clients=$4 pinned=$5
[[ "$host" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+localhost$ ]] || exit 2
[[ "$port" =~ ^[0-9]{4,5}$ && "$clients" =~ ^[0-9a-fA-F.:[:space:]]+$ ]] || exit 2
exec 9>/run/lock/bilimbi-local-https.lock
flock 9
main=/etc/caddy/Caddyfile
directory=/etc/caddy/bilimbi
site="$directory/$host.caddy"
owner="# Bilimbi checkout: $root"
[[ ! -f "$site" || $(head -n 1 "$site") == "$owner" ]] || {
    echo "The Caddy site $host belongs to another checkout; choose a distinct BILIMBI_DEV_HOST." >&2
    exit 1
}
available() {
    local candidate=$1 fragment listener pid
    # Installed fragments reserve ports even while another checkout compiles.
    for fragment in "$directory"/*.caddy; do
        [[ -f "$fragment" && "$fragment" != "$site" ]] || continue
        if grep -Eq "reverse_proxy[[:space:]]+127\\.0\\.0\\.1:$candidate([[:space:]]|$)" "$fragment"; then return 1; fi
    done
    listener=$(ss -H -ltnp "sport = :$candidate")
    [[ -n "$listener" ]] || return 0
    pid=$(printf '%s' "$listener" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
    # Reconfiguring the same site is safe; a new site cannot take its listener.
    [[ -f "$site" && -n "$pid" && $(readlink "/proc/$pid/cwd" 2>/dev/null || true) == "$root" ]]
}
while ! available "$port"; do
    if [[ "$pinned" == 1 ]]; then
        echo "PORT=$port is occupied or reserved by another instance; no process was stopped." >&2
        exit 1
    fi
    port=$((port + 1))
    (( port <= 65535 )) || { echo "No development port available" >&2; exit 1; }
done
install -d -o root -g caddy -m 0750 "$directory/certs"
backup=$(mktemp -d /etc/caddy/.bilimbi-backup.XXXXXX)
cp -p "$main" "$backup/main"
[[ ! -f "$site" ]] || cp -p "$site" "$backup/site"
for suffix in .pem -key.pem; do
    [[ ! -f "$directory/certs/$host$suffix" ]] || cp -p "$directory/certs/$host$suffix" "$backup/cert$suffix"
done
rollback=1
cleanup() {
    if [[ "$rollback" == 1 ]]; then
        cp -p "$backup/main" "$main"
        if [[ -f "$backup/site" ]]; then cp -p "$backup/site" "$site"; else rm -f -- "$site"; fi
        for suffix in .pem -key.pem; do
            if [[ -f "$backup/cert$suffix" ]]; then
                cp -p "$backup/cert$suffix" "$directory/certs/$host$suffix"
            else
                rm -f -- "$directory/certs/$host$suffix"
            fi
        done
    fi
    rm -f -- "$backup/main" "$backup/site" "$backup/cert.pem" "$backup/cert-key.pem" "$backup/validation"
    rmdir -- "$backup"
}
trap cleanup EXIT

install -o root -g caddy -m 0644 "$root/.local/https/$host.pem" "$directory/certs/$host.pem"
install -o root -g caddy -m 0640 "$root/.local/https/$host-key.pem" "$directory/certs/$host-key.pem"
cat > "$site" <<EOF
$owner
$host {
    tls $directory/certs/$host.pem $directory/certs/$host-key.pem
    @remote not remote_ip $clients
    respond @remote "Local development only" 403
    encode zstd gzip
    reverse_proxy 127.0.0.1:$port
}
EOF
chmod 0644 "$site"
if ! grep -Eq '^[[:space:]]*import[[:space:]]+/etc/caddy/bilimbi/\*\.caddy[[:space:]]*$' "$main"; then
    printf '\n# Bilimbi local development\nimport /etc/caddy/bilimbi/*.caddy\n' >> "$main"
fi
if ! runuser -u caddy -- caddy validate --config "$main" --adapter caddyfile > "$backup/validation" 2>&1; then
    cat "$backup/validation" >&2
    exit 1
fi
systemctl reload caddy
rollback=0
echo "Shared Caddy configuration validated and reloaded." >&2
printf '%s\n' "$port"

# Generic CLI resolvers use /etc/hosts; browsers also recognize .localhost.
if ! getent hosts "$host" >/dev/null; then
    printf '127.0.0.1\t%s # Bilimbi local HTTPS\n' "$host" >> /etc/hosts
fi
