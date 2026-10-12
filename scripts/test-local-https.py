#!/usr/bin/env python3
"""Smoke-test the running local Caddy/Phoenix boundary with certificate validation."""
import http.client
import json
import os
import ssl
import subprocess
from pathlib import Path

config_path = Path(__file__).resolve().parent.parent / ".local/config.json"
instance = json.loads(config_path.read_text()).get("https", {}) if config_path.exists() else {}
host = os.environ.get("BILIMBI_DEV_HOST", instance.get("host", "bilimbi.localhost"))
url = f"https://{host}"
context = ssl.create_default_context()


def request(path, source_address=None):
    connection = http.client.HTTPSConnection(
        host, context=context, timeout=20, source_address=source_address
    )
    try:
        connection.request("GET", path)
        response = connection.getresponse()
        return response.status, response.headers, response.read()
    finally:
        connection.close()


status, headers, body = request("/")
assert status == 200 and b'id="login-form"' in body, "Sign-in page did not load"
assert "secure" in headers.get("Set-Cookie", "").lower(), "Session cookie lacks Secure"

status, _, body = request("/.well-known/oauth-authorization-server")
assert status == 200
metadata = json.loads(body)
assert metadata["issuer"] == url
for key in ("device_authorization_endpoint", "token_endpoint"):
    assert metadata[key].startswith(url + "/"), f"Wrong {key}"
connection = http.client.HTTPConnection("127.0.0.1", int(os.environ.get("PORT", instance.get("port", 4000))))
connection.request("GET", "/")
response = connection.getresponse()
assert response.status == 301 and response.headers["Location"] == url + "/"
response.read()
connection.close()

# A local process bound to the virtual Ethernet address represents a peer
# outside the loopback/Windows-gateway allowlist, without exposing a listener.
interfaces = json.loads(subprocess.check_output(["ip", "-j", "-4", "addr", "show"]))
addresses = [
    address["local"] for interface in interfaces if interface["ifname"] != "lo"
    for address in interface["addr_info"] if address["scope"] == "global"
]
if addresses:
    status, _, _ = request("/", source_address=(addresses[0], 0))
    assert status == 403, "Caddy accepted a peer outside the local allowlist"
print("Local HTTPS smoke passed: TLS, cookies, redirects, OAuth discovery and local access boundary.")
