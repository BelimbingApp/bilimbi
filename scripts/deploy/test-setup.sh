#!/usr/bin/env bash
# Exercise the real Docker adapter with command doubles, without host mutation.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export SETUP_TEST_LOG=$test_dir/commands
mkdir "$test_dir/bin"
touch "$test_dir/release.env"
chmod 0600 "$test_dir/release.env"
export PATH="$test_dir/bin:$PATH"
cat > "$test_dir/bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$SETUP_TEST_LOG"
printf 'image=%s\n' "${BILIMBI_IMAGE:-}" >> "$SETUP_TEST_LOG"
case "$*" in
  'inspect --format {{.Image}} old-container') echo sha256:previous ;;
  *'ps -q app') [[ ${PREVIOUS_CONTAINER:-yes} == yes ]] && echo old-container; exit 0 ;;
  *'run --rm --no-deps -T'*'Release.bootstrap()')
    IFS= read -r password
    [[ "$password" == "${EXPECTED_PASSWORD:-test-password}" ]] || exit 42
    ;;
  *'run --rm --no-deps -T'*"${REFUSE_STEP:-none}") exit 43 ;;
  *'run --rm --no-deps -T'*'Release.adopt()')
    # Deliberately drain stdin like the real Compose client.
    cat >/dev/null
    ;;
  *'run --rm --no-deps -T'*) cat >/dev/null ;;
esac
SH
cat > "$test_dir/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s' "${HEALTH_STATUS:-200}"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_dir/bin/sleep"
chmod +x "$test_dir/bin/"*

run() { bash "$root/scripts/setup-docker.sh" "$@"; }
contains() { grep -q -- "$1" "$SETUP_TEST_LOG"; }
absent() { if contains "$1"; then echo "Unexpected command: $1" >&2; exit 1; fi; }
reset_log() { : > "$SETUP_TEST_LOG"; }

reset_log
printf 'test-password\n' | run install bilimbi:test "$test_dir/release.env" Tenant Company code Admin admin@example.com
contains 'Release.migrate()'
contains 'Release.bootstrap()'
absent test-password
absent 'Release.adopt()'

reset_log
printf ' test-password \n' | EXPECTED_PASSWORD=' test-password ' run install bilimbi:test "$test_dir/release.env" Tenant Company code Admin admin@example.com
contains 'Release.bootstrap()'
absent test-password

reset_log
run upgrade bilimbi:test "$test_dir/release.env"
contains 'Release.migrate()'
absent 'Release.bootstrap()'
absent 'Release.seed()'
absent 'Release.adopt()'

reset_log
run adopt bilimbi:test "$test_dir/release.env"
steps=$(grep -o 'Release\.[a-z_]*()' "$SETUP_TEST_LOG" | tr '\n' ' ')
[[ "$steps" == 'Release.verify() Release.adopt() Release.remap_dry_run() Release.remap() Release.migrate() Release.seed() ' ]]
absent 'Release.bootstrap()'

for refused in verify adopt remap_dry_run remap; do
  reset_log
  if REFUSE_STEP="Release.$refused()" run adopt bilimbi:test "$test_dir/release.env"; then exit 1; fi
  absent 'Release.migrate()'
  absent 'up -d'
done

reset_log
if HEALTH_STATUS=503 run upgrade bilimbi:test "$test_dir/release.env"; then exit 1; fi
contains 'up -d'
contains 'image=sha256:previous'
absent 'Release.bootstrap()'

reset_log
if HEALTH_STATUS=503 PREVIOUS_CONTAINER=no run upgrade bilimbi:test "$test_dir/release.env"; then exit 1; fi
contains 'stop app'

reset_log
if run upgrade bilimbi:latest "$test_dir/release.env"; then exit 1; fi
absent 'Release.migrate()'

echo 'Deployment adapter tests passed'
