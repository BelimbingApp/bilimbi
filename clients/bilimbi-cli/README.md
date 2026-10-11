# Bilimbi native client and Codex plugin

One native executable connects to any Bilimbi adopter's server. Give it the
server address once, approve device sign-in, and use the same plugin across
several profiles. Files stay in the harness. The client calls the API and
serves review/results on the desktop's `127.0.0.1`; it does not run AI.

## Install on a Windows office PC

1. Install and sign into your company's supported local Codex desktop client.
   Its agent must be able to run programs on this PC and reach your Bilimbi
   server. Codex running on a remote machine uses that machine's network,
   browser address and credential store instead.
2. Get the `bilimbi-windows-amd64.zip` package from your administrator or the
   **Native client** artifact on a passing Bilimbi CI run. Extract the entire
   ZIP into a permanent folder, such as `C:\Users\YourName\BilimbiPlugin`.
   Keep the hidden `.agents` folder. There is one executable at
   `plugins\bilimbi\bin\bilimbi.exe`; no Node, Python or MCP installation is needed.
3. Add that extracted marketplace with one command in PowerShell:

   ```powershell
   codex plugin marketplace add "$env:USERPROFILE\BilimbiPlugin"
   ```

   This assumes your installed Codex CLI is on PATH. If it is not, have the
   local Codex agent run the command using its CLI location. Registration
   makes the plugin discoverable; it does not sign you into Bilimbi.
4. Restart the desktop client. Open its Plugins Directory, select the
   **Bilimbi** local marketplace, and install/enable **bilimbi**. Start a new
   conversation. Local plugin UI availability depends on the installed Codex
   surface and your organization's plugin policy.
5. Ask: “Use Bilimbi to look up a company.” Give your server address, for
   example `http://bilimbi.office:4000`. The agent runs `login` and shows a
   browser address and code. Open the address, sign into Bilimbi, check the
   stated agent/company, enter the code and approve. The program polls and
   saves the connection in Windows Credential Manager. Never paste a token
   into the conversation.
6. For another adopter, give its address and a distinct profile name. Ask the
   agent to switch with `use <name>`. `profiles` lists servers without secrets.

These packages are unsigned. Code signing and macOS notarization are follow-up
release work; use your organization's executable distribution policy. HTTPS
server deployment is separately deferred by ADR 0021. This client accepts the
server's HTTP or HTTPS address and uses the OS trust store for HTTPS.

Packaging follows the [official OpenAI plugin documentation](https://developers.openai.com/plugins/build/plugins):
a portable root manifest, a discoverable skill and a local marketplace. No
MCP, hooks, app registration or automatic companion-runtime installer is used.
The repository marketplace can also be registered with
`codex plugin marketplace add <repository-root>` after building its binary.
Release archives relocate the plugin to `plugins/bilimbi` and ship a matching
marketplace. The repository version lives at `plugins/codex/bilimbi`.

## Commands

`bilimbi help` lists commands. Each successful command prints JSON to stdout;
errors print a JSON error to stderr and exit 1. Device codes and local browser
addresses print to stderr. Header flags may occur before or after the command.

```text
bilimbi login http://bilimbi.office:4000 --name office --agent-id codex/gpt-6.1-high
bilimbi profiles
bilimbi use office
bilimbi search company --agent-id codex/gpt-6.1-high --run-id task-123
bilimbi describe <operation-key> --agent-id codex/gpt-6.1-high --run-id task-123
bilimbi guide <guide-key> --agent-id codex/gpt-6.1-high --run-id task-123
bilimbi call <operation-key> --input input.json --agent-id codex/gpt-6.1-high --run-id task-123
bilimbi logout office
```

`BILIMBI_AGENT_ID` and `BILIMBI_RUN_ID` are equivalent to the flags. Use the
actual `harness/model-ver-effort`, not the example when a different model runs.
`call` reads one JSON object from stdin by default (`--input -`). It describes
the operation first and refuses every kind except `read`. This release has no
direct write call. Supported writes use `plan`, review, `commit` and report.

Discovery verifies API version 1, the public `bilimbi-native` client and both
OAuth grants. Endpoints must stay on the supplied origin; redirects are
refused. Use the canonical server address rather than a redirecting alias.
Access tokens expire after an hour. The client rotates the refresh token before
expiry under a profile-store lock, persists the replacement, and never retries
a failed rotation. The lock is an operating-system file lock held only while
the profile is read, refreshed and saved, never during the API request, so
parallel commands do not block each other. Uncertainty is persisted before rotation, so a lost response
or crash requires signing in again rather than retrying on the next command.

Profiles live in the OS user configuration directory's `bilimbi/profiles.json`.
Credentials are keyed by a hash of the server origin, not by profile name.
macOS uses the native Keychain API (built with cgo), Windows uses Credential
Manager, and Linux uses Secret Service through D-Bus. The dependency is limited
to those three backends; it cannot invoke password-manager shell commands.
When the native store is unavailable, a private mode-600 credential
file under `bilimbi/credentials` is the fallback, and `login` prints a
warning to stderr when it is used. Profiles state which backend
was used. Windows enforces the equivalent protected, current-user-only ACL
before writing bytes because Unix mode bits cannot restrict Windows access. A temporarily unavailable
store holding an existing token is never silently replaced by a file.

`logout` deletes credentials and all aliases for that server. It does not revoke
the connection on the server; use Bilimbi's **Connected agents** page for that.
The operating system releases the profile lock if a command is killed, so a
crash never leaves it behind. Do not run simultaneous sign-ins to the same
server.

## Safe write loop

Create an input file containing `{"operations":[{"key":"core.company.create",
"input":{"name":"Example"}}]}` after discovering the operation and searching
for duplicates. Run `bilimbi plan --input operations.json > plan.json`, then
`bilimbi review --input plan.json --session review-session.json` and wait for
its submission. The page shows the server's validated changes, defaults and
expiry. Those evidence cells are read-only; changes belong in the comments,
followed by a new plan and review. Ordinary local presentation documents retain
editable cells. No business write happens until commit.

The client enforces the person's go locally; Bilimbi does not verify it. When
`review` receives the plan output unchanged from `plan` and the person approves,
it writes an approval marker for that plan code beside the plan file, only if the
reviewed operations match the saved ones. `bilimbi commit --plan <code> >
report.json` refuses without that marker, so a review of one plan never unlocks
another, and a successful commit deletes the plan file and its marker. It sends
the exact saved operations to the same server. Plans are private files below the
OS configuration directory's `bilimbi/plans`, bound to their server origin;
credentials remain separate. Any `plan`, `review` approval or `commit` first
deletes plans that have expired. Commit requires a locally available code and
the matching active server. There is no automatic write retry. Expired or
changed plans require a fresh dry run and go. If a commit response fails, the
plan and marker remain until expiry: search or read the records to establish
what happened before making another plan.

`bilimbi report --input report.json --session review-session.json` shows the
committed records and server-supplied verification links in the same tab.
Company managers can turn writes off on the company page. Permissions, field
restrictions and company workflows are checked again on commit.

## Local review and report contract

Both commands read a presentation document from `--input <file|->`:

```json
{
  "title": "Company review",
  "summary": "Check the names and leave any questions.",
  "columns": [{"key": "name", "label": "Name"}],
  "rows": [{"name": "Example company", "record_id": "12"}],
  "links": [{"label": "Company in Bilimbi", "url": "http://bilimbi.office:4000/companies/12"}]
}
```

Column keys determine editable fields. Other row data is retained. Strings
are plain text (browser CRLF line endings return as `\n`), numbers and booleans have typed controls, and structured/null
values use JSON. An empty row list is valid; the page reports no records.
Links must be HTTP(S) and must come from verified record addresses.
Documents and submissions are capped at 8 MiB. They are never sent to Bilimbi.

`review --input review.json` listens on a random `127.0.0.1` port at a random,
one-session path, waits for a submission, prints JSON and exits. The person
can edit cells, comment/question, and approve or request changes. The result is:

```json
{"approved": true, "comment": "", "document": {"title": "Company review", "columns": [{"key": "name", "label": "Name"}], "rows": [{"name": "Edited company", "record_id": "12"}]}}
```

For the same page to become a report, run
`review --input review.json --session session.json` as a harness-managed
background process. It writes the private local address into a mode-600 session
file, prints the submission as soon as it arrives, then waits. The harness
reads the submitted JSON before deciding its next action. Run
`report --input results.json --session session.json` to replace the waiting
page with results and verification links. The browser refreshes the waiting
page; **Close report** ends its server and removes the session file.
`report --input results.json` can also serve a standalone report.

The default lifetime is 30 minutes; `--timeout 1h` changes it. Expiry or Ctrl+C
closes the listener and removes the session file. Without a session file,
review closes immediately after its submission. Requested changes start a new
review; the old page can show a report explaining what remains unresolved.
The one-session path and descriptor are access capabilities: keep them local.
Host/origin checks refuse cross-site submissions and DNS rebinding. HTML is
escaped, no external assets load, and forms work without JavaScript.

This document is deliberately independent of a Bilimbi plan. Job 4 supplies
server previews and plan codes, checks edited input again, performs the write
and fills the report. Local approval currently performs no mutation.

## Build and verify

Go is chosen for a single distributable program, standard-library HTTP/JSON,
embedded HTML and Windows/Linux cross-compilation. It needs no user-side
interpreter. Go's standard library has no credential-store abstraction;
`99designs/keyring` provides native Windows/macOS and D-Bus Linux access, with
an explicit backend allowlist. macOS builds link only to system frameworks;
Linux and Windows builds use `CGO_ENABLED=0`.

From `clients/bilimbi-cli`, with Go **1.27.2**:

```sh
go test -race ./...
go vet ./...
go build -trimpath -buildvcs=false -o /tmp/bilimbi .
go run ./pack --root ../.. --binary /tmp/bilimbi --target linux-amd64 --output /tmp/bilimbi-linux-amd64.zip
```

Build macOS on macOS with cgo enabled so the credential backend is present;
do not ship a Darwin cgo-disabled binary. Build Windows with
`CGO_ENABLED=0 GOOS=windows GOARCH=amd64`, and Linux x64 similarly. To develop the
repository plugin, put the local build in `plugins/codex/bilimbi/bin/` (ignored
by Git). CI tests on Linux, macOS and Windows, builds all four targets, and
uploads ZIP marketplaces plus SHA-256 files. No binaries are committed.

The tests use fake API/device servers and injected credential stores; they
never authenticate to an adopter or change the machine's credential store.
They cover discovery confinement, polling/backoff/refusal, refresh persistence,
redaction, profiles/fallback/locks, read-only dispatch and review/report lifecycle.
