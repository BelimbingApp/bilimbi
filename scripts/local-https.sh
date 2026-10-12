#!/usr/bin/env bash
# Host bootstrap used by mix bilimbi.server. mkcert shares Belimbing's local
# CA when CAROOT is set; only the public CA certificate crosses into Windows.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mode=${1:-}
fail() { echo "$*" >&2; exit 1; }
[[ "$mode" == --prepare || "$mode" == --configure || "$mode" == --verify ]] || fail "Usage: local-https.sh --prepare|--configure|--verify [HOST.localhost] [PORT]"
if [[ -n ${BILIMBI_ELIXIR:-} ]]; then
    elixir_command=("$BILIMBI_ELIXIR")
elif command -v elixir >/dev/null; then
    elixir_command=(elixir)
elif command -v mise >/dev/null; then
    elixir_command=(mise exec -- elixir)
else
    fail "Elixir is required. Install the pinned toolchain with mise install."
fi
settings=$("${elixir_command[@]}" "$root/scripts/local-config.exs" https "$root")
readarray -t settings <<< "$settings"
host=${2:-${settings[0]}}
port=${3:-${settings[1]}}
# Localhost names resolve to loopback in browsers. No public DNS or ACME.
[[ "$host" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+localhost$ && ${#host} -le 253 ]] || fail "BILIMBI_DEV_HOST must be a lowercase name under .localhost."
IFS=. read -r -a labels <<< "$host"
for label in "${labels[@]}"; do
    (( ${#label} <= 63 )) || fail "Each hostname label must contain at most 63 characters."
done
if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1024 || 10#$port > 65535 )); then
    fail "PORT must be between 1024 and 65535."
fi
port=$((10#$port))
url="https://$host"
state="$root/.local/https"
mkdir -p "$state"

if [[ "$mode" == --verify ]]; then
    # --resolve also supports CLI resolvers that do not special-case .localhost.
    curl --fail --silent --show-error --max-time 20 --resolve "$host:443:127.0.0.1" \
        "$url/.well-known/oauth-authorization-server" | \
        python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("issuer") == sys.argv[1] else "HTTPS answered, but OAuth advertises a different issuer. Restart the correct checkout.")' "$url"
    echo "Bilimbi is ready: $url"
    exit 0
fi

for tool in caddy mkcert openssl curl python3 ss sudo flock sha256sum; do
    command -v "$tool" >/dev/null || fail "Missing $tool. Install local HTTPS prerequisites: sudo apt install caddy mkcert libnss3-tools"
done
identifier=$(printf '%s' "$root" | sha256sum | cut -c1-10)
exec 8>"/tmp/bilimbi-local-https-$(id -u).lock"
flock 8
site="/etc/caddy/bilimbi/$host.caddy"
if [[ -f "$site" && $(head -n 1 "$site") != "# Bilimbi checkout: $root" ]]; then
    [[ ${BILIMBI_HOST_PINNED:-0} != 1 ]] || fail "The hostname $host belongs to another checkout."
    host="bilimbi-$identifier.localhost"
    url="https://$host"
fi
if [[ "$mode" == --prepare ]]; then
    # Never replace a live instance. A repeat reports the current address;
    # unrelated listeners are handled by the allocator under Caddy's lock.
    listener=$(ss -H -ltnp "sport = :$port")
    pid=$(printf '%s' "$listener" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
    if [[ -n "$pid" && $(readlink "/proc/$pid/cwd" 2>/dev/null || true) == "$root" ]]; then
        metadata=$(curl --fail --silent --max-time 5 --resolve "$host:443:127.0.0.1" \
            "$url/.well-known/oauth-authorization-server" || true)
        if python3 -c 'import json,sys; sys.exit(json.loads(sys.argv[1]).get("issuer") != sys.argv[2])' "$metadata" "$url" 2>/dev/null; then
            echo "This Bilimbi instance is already running: $url"
            exit 10
        fi
        if [[ -f "/etc/caddy/bilimbi/$host.caddy" ]]; then
            fail "This checkout already has a server on port $port, but its HTTPS endpoint is unhealthy. Restart that server to apply configuration changes."
        fi
    fi
fi
systemctl is-active --quiet caddy || fail "Start the shared Caddy service first: sudo systemctl start caddy"

# Use the existing CA rather than generating a per-checkout trust root. Fail
# when trust cannot be installed; never substitute curl -k or a TLS fallback.
mkcert -install
ca_root=$(mkcert -CAROOT)
if command -v powershell.exe >/dev/null && command -v wslpath >/dev/null; then
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$(wslpath -w "$root/scripts/trust-local-ca.ps1")" \
        -CertificatePath "$(wslpath -w "$ca_root/rootCA.pem")"
fi
certificate="$state/$host.pem"
key="$state/$host-key.pem"
if [[ ! -f "$certificate" || ! -f "$key" ]] || \
    ! openssl x509 -in "$certificate" -checkend 2592000 -noout >/dev/null 2>&1 || \
    ! openssl verify -CAfile "$ca_root/rootCA.pem" -verify_hostname "$host" "$certificate" >/dev/null 2>&1; then
    (umask 077; mkcert -cert-file "$certificate" -key-file "$key" "$host")
fi

# NAT-mode WSL clients reach the shared listener through the Windows virtual
# gateway. Allow that local host as well as loopback, without allowing LAN peers.
clients="127.0.0.1 ::1"
if command -v wslinfo >/dev/null && [[ $(wslinfo --networking-mode) == nat ]]; then
    gateway=$(ip -4 route show default | awk 'NR == 1 {print $3}')
    [[ "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Could not resolve the Windows WSL gateway."
    clients+=" $gateway"
fi
port=$(sudo bash "$root/scripts/local-https/install-caddy.sh" "$root" "$host" "$port" "$clients" "${BILIMBI_PORT_PINNED:-0}")
"${elixir_command[@]}" "$root/scripts/local-config.exs" save-https "$root" "$host" "$port"
printf 'Local HTTPS configured: %s → 127.0.0.1:%s\n' "$url" "$port"
