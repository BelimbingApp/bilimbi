---
name: bilimbi-setup
description: Set up or diagnose Bilimbi through connected MCP tools and OAuth, or check its native executable and connect with device sign-in in a local runtime.
---

Read [the Bilimbi workflow](../bilimbi/SKILL.md). If Bilimbi MCP tools are
connected, use `search` for the requested task (or company for a connection
test), and complete OAuth linking through the host if prompted. Report the
operations actually returned, then continue the task. No native program is
needed for MCP.

If no MCP connection exists and no local process tool is available, explain
that the administrator must connect this installation's HTTPS `/mcp` endpoint
in ChatGPT Plugins with its registered OAuth client. A local skill package
alone cannot register a server.

For the native client, perform the workflow's startup checks.
Run the commands yourself when the host supplies local process tools.
Installing a skill does not itself provide a shell or register API tools.

Run `help` and `profiles` before asking the person for information. If there is
no suitable profile, obtain the server address and run `discover <address>`.
This checks API compatibility without signing in or saving credentials. Use
the canonical address configured by the server; never bypass an origin refusal.
Then run `login` with the identity and run flags from the workflow, show the
device address and user code, and keep polling until approval or expiry.

After sign-in, run `profiles` and `search` for the person's requested task (or
`search company` for a connection test). Report the server and available
operations actually returned. Authentication, permission refusals and empty
results are distinct outcomes. A successful `help` alone does not prove a
working connection. Continue the requested task through the Bilimbi workflow.
