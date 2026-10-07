#!/usr/bin/env bash
# Run ONLY in a disposable Ubuntu container; root paths below are test fixtures.
set -euo pipefail
[[ ${CI:-} == true && -f /.dockerenv && $EUID -eq 0 ]] || {
  echo "Disposable CI container required" >&2; exit 2;
}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export SETUP_TEST_LOG=$test_dir/commands
mkdir -p "$test_dir/scripts/deploy" "$test_dir/bin"
cp "$root/scripts/setup-native.sh" "$test_dir/scripts/"
cp "$root/scripts/deploy/bilimbi.service" "$test_dir/scripts/deploy/"
export PATH="$test_dir/bin:$PATH"
cat > "$test_dir/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$SETUP_TEST_LOG"
SH
cat > "$test_dir/bin/caddy" <<'SH'
#!/usr/bin/env bash
printf 'caddy %s\n' "$*" >> "$SETUP_TEST_LOG"
SH
cat > "$test_dir/scripts/deploy/setup-ubuntu.sh" <<'SH'
#!/usr/bin/env bash
printf 'prepare\n' >> "$SETUP_TEST_LOG"
mkdir -p /etc/bilimbi /etc/caddy /etc/systemd/system /opt/bilimbi/releases
SH
cat > "$test_dir/scripts/deploy/deploy.sh" <<'SH'
#!/usr/bin/env bash
printf 'deploy %s\n' "$*" >> "$SETUP_TEST_LOG"
[[ ${REFUSE_DEPLOY:-no} == no ]]
SH
cat > "$test_dir/scripts/deploy/bootstrap-admin.sh" <<'SH'
#!/usr/bin/env bash
printf 'bootstrap %s\n' "$*" >> "$SETUP_TEST_LOG"
SH
cat > "$test_dir/scripts/deploy/seed.sh" <<'SH'
#!/usr/bin/env bash
printf 'seed\n' >> "$SETUP_TEST_LOG"
SH
chmod +x "$test_dir/bin/"*
printf 'CONFIG=original\n' > "$test_dir/release.env"
printf 'example.com { reverse_proxy localhost:4000 }\n' > "$test_dir/Caddyfile"
touch "$test_dir/archive"
run() { bash "$test_dir/scripts/setup-native.sh" "$@"; }
contains() { grep -q -- "$1" "$SETUP_TEST_LOG"; }
absent() { if contains "$1"; then echo "Unexpected command: $1" >&2; exit 1; fi; }
reset_log() { : > "$SETUP_TEST_LOG"; }
install_args=(install "$test_dir/archive" test "$test_dir/release.env" "$test_dir/Caddyfile"
  Tenant Company code Admin admin@example.com)

reset_log
run "${install_args[@]}"
contains prepare
contains 'bootstrap Tenant Company code Admin admin@example.com'
[[ $(stat -c '%a:%U' /etc/bilimbi/bilimbi.env) == 600:root ]]
cmp "$test_dir/release.env" /etc/bilimbi/bilimbi.env

printf '\n# operator edit\n' >> /etc/systemd/system/bilimbi.service
cp /etc/systemd/system/bilimbi.service "$test_dir/operator.service"
reset_log
run "${install_args[@]}"
cmp "$test_dir/operator.service" /etc/systemd/system/bilimbi.service

reset_log
run upgrade "$test_dir/archive" test
contains deploy
absent prepare
absent bootstrap
absent seed

reset_log
run adopt "$test_dir/archive" test "$test_dir/release.env" "$test_dir/Caddyfile"
contains '5 adopt'
contains seed
absent bootstrap

reset_log
if REFUSE_DEPLOY=yes run "${install_args[@]}"; then exit 1; fi
absent bootstrap

printf 'CONFIG=changed\n' > "$test_dir/release.env"
reset_log
if run "${install_args[@]}"; then exit 1; fi
absent prepare
absent deploy
grep -qx 'CONFIG=original' /etc/bilimbi/bilimbi.env

printf 'ID=unsupported\nVERSION_ID=1\n' > /etc/os-release
reset_log
if run upgrade "$test_dir/archive" test; then exit 1; fi
absent deploy
echo 'Native adapter tests passed'
