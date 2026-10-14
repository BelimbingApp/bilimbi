#!/usr/bin/env python3
"""Exercise checkout allocation and rollback against the shared local Caddy."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
env = os.environ.copy()
env.update(BILIMBI_HOST_PINNED="0", BILIMBI_PORT_PINNED="0")


def run(*arguments, environment=env):
    return subprocess.run(arguments, env=environment, capture_output=True, text=True)


def test_stale_site_pruning():
    """Exercise install-time pruning with all privileged paths redirected to a fixture."""
    with tempfile.TemporaryDirectory(prefix="caddy-prune-test-") as directory:
        fixture = Path(directory)
        caddy_root = fixture / "etc/caddy"
        caddy = caddy_root / "bilimbi"
        certs = caddy / "certs"
        certs.mkdir(parents=True)
        (caddy_root / "Caddyfile").write_text("# fixture caddyfile\n")
        hosts = fixture / "etc/hosts"
        hosts.parent.mkdir(parents=True, exist_ok=True)
        hosts.write_text(
            "127.0.0.1\told.localhost # Bilimbi local HTTPS\n"
            "127.0.0.1\tlive.localhost # Bilimbi local HTTPS\n"
        )

        stale_root = fixture / "deleted-checkout"
        stale_host = "old.localhost"
        (caddy / f"{stale_host}.caddy").write_text(
            f"# Bilimbi checkout: {stale_root}\n{stale_host} {{ reverse_proxy 127.0.0.1:4600 }}\n"
        )
        (certs / f"{stale_host}.pem").write_text("stale cert")
        (certs / f"{stale_host}-key.pem").write_text("stale key")

        live_root = fixture / "live-checkout"
        live_root.mkdir()
        live_host = "live.localhost"
        live_fragment = caddy / f"{live_host}.caddy"
        live_fragment.write_text(
            f"# Bilimbi checkout: {live_root}\n{live_host} {{ reverse_proxy 127.0.0.1:4601 }}\n"
        )
        live_bytes = live_fragment.read_bytes()
        (certs / f"{live_host}.pem").write_text("live cert")
        (certs / f"{live_host}-key.pem").write_text("live key")

        checkout = fixture / "new-checkout"
        https = checkout / ".local/https"
        https.mkdir(parents=True)
        new_host = "new.localhost"
        (https / f"{new_host}.pem").write_text("new cert")
        (https / f"{new_host}-key.pem").write_text("new key")

        redirected = fixture / "install-caddy.sh"
        source = (root / "scripts/local-https/install-caddy.sh").read_text()
        source = source.replace("/etc/caddy", str(caddy_root))
        source = source.replace("/etc/hosts", str(hosts))
        source = source.replace("/run/lock/bilimbi-local-https.lock", str(fixture / "lock"))
        source = source.replace("install -d -o root -g caddy -m 0750", "install -d")
        source = source.replace("install -o root -g caddy -m 0644", "install -m 0644")
        source = source.replace("install -o root -g caddy -m 0640", "install -m 0640")
        redirected.write_text(source)
        redirected.chmod(0o755)

        commands = fixture / "bin"
        commands.mkdir()
        for name in ("systemctl",):
            executable = commands / name
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
        runuser = commands / "runuser"
        runuser.write_text(
            "#!/bin/sh\n"
            "if [ -n \"${BILIMBI_TEST_FAIL_VALIDATE:-}\" ] && "
            "[ -e \"$BILIMBI_TEST_FAIL_VALIDATE\" ]; then exit 1; fi\n"
            "exit 0\n"
        )
        runuser.chmod(0o755)
        ss = commands / "ss"
        ss.write_text("#!/bin/sh\nexit 0\n")
        ss.chmod(0o755)
        environment = dict(env, PATH=f"{commands}:{os.environ['PATH']}")
        validation_failure = fixture / "fail-validation"
        validation_failure.touch()
        result = run(
            "sudo", "env", f"PATH={environment['PATH']}",
            f"BILIMBI_TEST_FAIL_VALIDATE={validation_failure}", "bash", str(redirected),
            str(checkout), new_host, "4600", "127.0.0.1 ::1", "1",
            environment=environment,
        )
        assert result.returncode != 0, "Validation failure did not abort the installation"
        assert (caddy / f"{stale_host}.caddy").exists()
        assert (certs / f"{stale_host}.pem").read_text() == "stale cert"
        assert (certs / f"{stale_host}-key.pem").read_text() == "stale key"
        assert "old.localhost # Bilimbi local HTTPS" in hosts.read_text()
        validation_failure.unlink()

        result = run(
            "sudo", "env", f"PATH={environment['PATH']}", "bash", str(redirected),
            str(checkout), new_host, "4600", "127.0.0.1 ::1", "1",
            environment=environment,
        )
        assert result.returncode == 0, result.stderr
        assert not (caddy / f"{stale_host}.caddy").exists()
        assert not (certs / f"{stale_host}.pem").exists()
        assert not (certs / f"{stale_host}-key.pem").exists()
        assert live_fragment.read_bytes() == live_bytes
        assert (certs / f"{live_host}.pem").read_text() == "live cert"
        assert "old.localhost # Bilimbi local HTTPS" not in hosts.read_text()
        assert "live.localhost # Bilimbi local HTTPS" in hosts.read_text()


if sys.argv[1:] == ["--prune-harness-only"]:
    test_stale_site_pruning()
    print("Stale Caddy site pruning harness passed.")
    raise SystemExit(0)

current = json.loads((root / ".local/config.json").read_text())["https"]
caddy = Path("/etc/caddy/bilimbi")
current_site = caddy / f'{current["host"]}.caddy'
before = current_site.read_bytes()


scratch = root / "tmp/local-https"
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="instance-test-", dir=scratch) as directory:
    checkout = Path(directory)
    host = "bilimbi-" + hashlib.sha256(str(checkout).encode()).hexdigest()[:10] + ".localhost"
    site = caddy / f"{host}.caddy"
    hosts_line = f"127.0.0.1\t{host} # Bilimbi local HTTPS\n"
    hosts_entry_existed = hosts_line in Path("/etc/hosts").read_text()
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
        owns_site = site.exists() and site.read_text().splitlines()[0] == f"# Bilimbi checkout: {checkout}"
        if owns_site:
            result = run("sudo", "rm", "--", str(site),
                         str(caddy / "certs" / f"{host}.pem"),
                         str(caddy / "certs" / f"{host}-key.pem"))
            assert result.returncode == 0, result.stderr
            result = run("sudo", "systemctl", "reload", "caddy")
            assert result.returncode == 0, result.stderr
        # The installer adds this exact line only when no resolver entry is
        # available. Remove it even if site cleanup already removed the
        # fragment, but preserve any entry that predated this fixture.
        if not hosts_entry_existed:
            cleanup_hosts = (
                "from pathlib import Path; import sys; p=Path('/etc/hosts'); "
                "line='127.0.0.1\\t'+sys.argv[1]+' # Bilimbi local HTTPS\\n'; "
                "p.write_text(p.read_text().replace(line,''))"
            )
            result = run("sudo", "python3", "-c", cleanup_hosts, host)
            assert result.returncode == 0, result.stderr
print("Instance smoke passed: automatic hostname/port allocation, stable repeats, conflict rejection and Caddy rollback.")
