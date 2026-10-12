#!/usr/bin/env python3
"""Exercise checkout allocation and rollback against the shared local Caddy."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
current = json.loads((root / ".local/config.json").read_text())["https"]
caddy = Path("/etc/caddy/bilimbi")
current_site = caddy / f'{current["host"]}.caddy'
before = current_site.read_bytes()
env = os.environ.copy()
env.update(BILIMBI_HOST_PINNED="0", BILIMBI_PORT_PINNED="0")


def run(*arguments, environment=env):
    return subprocess.run(arguments, env=environment, capture_output=True, text=True)


scratch = root / "tmp/local-https"
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="instance-test-", dir=scratch) as directory:
    checkout = Path(directory)
    host = "bilimbi-" + hashlib.sha256(str(checkout).encode()).hexdigest()[:10] + ".localhost"
    site = caddy / f"{host}.caddy"
    for filename in ("scripts/local-https.sh", "scripts/local-config.exs", "mix/local_config.exs",
                     "scripts/local-https/install-caddy.sh", "scripts/trust-local-ca.ps1"):
        destination = checkout / filename
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / filename, destination)
    script = str(checkout / "scripts/local-https.sh")
    instance_file = checkout / ".local/config.json"
    instance_file.parent.mkdir()
    database = {"name": "fixture_database", "password": "fixture-secret"}
    instance_file.write_text(json.dumps({"database": database}))
    try:
        result = run("bash", script, "--configure", "bilimbi.localhost", "4000")
        assert result.returncode == 0, result.stderr
        saved = json.loads(instance_file.read_text())
        assert saved["database"] == database, "HTTPS setup overwrote database settings"
        first = saved["https"]
        assert first["host"] == host and first["port"] != current["port"]
        assert current_site.read_bytes() == before, "Another instance's site was modified"

        result = run("bash", script, "--configure", "bilimbi.localhost", "4000")
        assert result.returncode == 0, result.stderr
        assert json.loads(instance_file.read_text()) == saved, "Repeated setup changed the config"

        pinned = dict(env, BILIMBI_PORT_PINNED="1")
        result = run("bash", script, "--configure", host, str(current["port"]), environment=pinned)
        assert result.returncode != 0 and "occupied or reserved" in result.stderr
        assert json.loads(instance_file.read_text()) == saved

        pinned = dict(env, BILIMBI_HOST_PINNED="1")
        result = run("bash", script, "--configure", current["host"], "4000", environment=pinned)
        assert result.returncode != 0 and "another checkout" in result.stderr

        # Prove rollback through a real validation failure, including the leaf
        # files that a failed certificate replacement would otherwise leave bad.
        installed = [Path("/etc/caddy/Caddyfile"), site,
                     caddy / "certs" / f"{host}.pem", caddy / "certs" / f"{host}-key.pem"]
        snapshot = [run("sudo", "cat", str(path)).stdout for path in installed]
        certificate = checkout / ".local/https" / f"{host}.pem"
        certificate.write_text("invalid certificate\n")
        result = run("sudo", "bash", str(checkout / "scripts/local-https/install-caddy.sh"),
                     str(checkout), host, str(first["port"]), "127.0.0.1 ::1", "1")
        assert result.returncode != 0, "Invalid certificate passed validation"
        assert [run("sudo", "cat", str(path)).stdout for path in installed] == snapshot
        assert current_site.read_bytes() == before
    finally:
        # Remove only this fixture's owned site and leaf files. Never touch its
        # mkcert CA or the other development sites.
        if site.exists():
            assert site.read_text().splitlines()[0] == f"# Bilimbi checkout: {checkout}"
            result = run("sudo", "rm", "--", str(site),
                         str(caddy / "certs" / f"{host}.pem"),
                         str(caddy / "certs" / f"{host}-key.pem"))
            assert result.returncode == 0, result.stderr
            result = run("sudo", "systemctl", "reload", "caddy")
            assert result.returncode == 0, result.stderr
            cleanup_hosts = (
                "from pathlib import Path; import sys; p=Path('/etc/hosts'); "
                "line='127.0.0.1\\t'+sys.argv[1]+' # Bilimbi local HTTPS\\n'; "
                "p.write_text(p.read_text().replace(line,''))"
            )
            result = run("sudo", "python3", "-c", cleanup_hosts, host)
            assert result.returncode == 0, result.stderr
print("Instance smoke passed: automatic hostname/port allocation, stable repeats, conflict rejection and Caddy rollback.")
