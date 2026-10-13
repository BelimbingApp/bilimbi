# Base Artifacts

`base/artifacts` stores sensitive uploaded and generated business documents.
Domain modules use `Bilimbi.Base.Artifacts` rather than exposing private files.
This module provides private storage, a simple PDF serializer and the Base PDF
port: HTML printing, single-use signed render URLs, AES-256 protection and queued
completion events. Business modules own document workflows and templates.

## Owning-module integration

Declare a descriptor dependency on `base/artifacts`. Implement the
`Bilimbi.Base.Artifacts.Owner` behaviour in a trusted server-selected adapter:

- `artifact_owner_id/0` returns the business module's stable logical ID.
- `authorize(scope, company_id, operation, reference)` returns literal `:ok`
  only when the company is live, belongs to the tenant scope, and the current
  scope actor may perform `:create`, `:read`, `:delete` or `:retain` on that
  business subject. For `:purge`, the reference is nil and the check must grant
  company maintenance access.
  Recheck current permissions and subject state every time.

The Domain adapter validates Company through its public API. Base has no
upward Core dependency or private Company query; a positive ID alone does not
validate Company identity. Base scopes its own rows by tenant/company and binds
both the stable owner ID and adapter module name. An unrelated adapter cannot
replace the stored document's authority. Adapter renames require an explicit
owner-reviewed migration. Select adapters in code, never from request params.

References are `%{subject: "opaque-record-id", kind: "evidence"}`. Use durable
identifiers, rather than names or personal information. Document contents,
filenames and PDF input data never enter audit payloads. Base verifies the sealed
scope actor and refuses an actor bound to a different company even if the owner
would grant it. System scopes have no inherent permission: the owner must
explicitly authorize maintenance and named system principals.

```elixir
alias Bilimbi.Base.Artifacts

# DocumentOwner is implemented in the calling Domain module.
reference = %{subject: subject_id, kind: "evidence"}
{:ok, document} =
  Artifacts.put(scope, company_id, DocumentOwner, reference, bytes, content_type)
{:ok, %{bytes: bytes, metadata: metadata}} =
  Artifacts.read(scope, company_id, DocumentOwner, document.id)
{:ok, :deleted} = Artifacts.delete(scope, company_id, DocumentOwner, document.id)
```

Metadata contains ID, subject, kind, content type, byte size, SHA-256, expiry,
retain-until and legal-hold time; it exposes no Ecto schema or storage path.
MIME type is owner-supplied metadata, not a content safety claim. The owner
validates accepted uploads and any needed scanning/quarantine before storage.
Its authenticated download adapter calls `read/4` on every request and delivers
an attachment with private/no-store cache headers and content sniffing
disabled. Never cache bytes for later callers.

Call this API outside a Repo transaction. Files require durable reservation and
tombstone commits before filesystem IO and cannot participate in an outer
rollback. The owner retains business provenance and references; Base owns the
byte lifecycle. Core Company deletion/archive policy remains with the owner.

## PDF generation

The same adapter can implement `Bilimbi.Base.Artifacts.PDF`:
`render_pdf(scope, company_id, reference, data)` returns `{:ok, pdf_binary}`
or `{:error, reason}`. Call:

```elixir
Artifacts.generate_pdf(scope, company_id, DocumentOwner, reference, document_data)
```

Base authorizes before rendering, checks the PDF header, applies the configured
size limit and stores through the upload seam as `application/pdf`. It rechecks
authority before publication. The renderer owns valid PDF construction,
templates and data selection; the header check is not a complete PDF validator.
Use `Bilimbi.Base.Artifacts.PDF.Renderer.render/1` for simple text and table
documents instead of maintaining a domain-local PDF serializer. It is a pure
Elixir serializer with no additional dependency, executable or external service.
The owner still selects business data and templates and implements the existing
PDF behaviour; this helper does not authorize or store anything on its own.
Renderers must not fetch untrusted resources or log contents.

```elixir
# Inside the trusted owner's render_pdf/4 callback, after selecting permitted data:
Bilimbi.Base.Artifacts.PDF.Renderer.render(%{
  title: "Record summary",
  metadata: %{author: "Document owner", subject: "Record review", keywords: "summary"},
  blocks: [
    {:text, "Facts selected by the owning module.\nA second line."},
    {:table, ["Record", "Value"], [["A", "12.50"], ["B", "8.00"]]},
    :page_break,
    {:text, "Additional notes"}
  ]
})
```

`title` and `blocks` are required; `metadata` is optional. All text and table
cells must be strings; format dates and exact numbers in the owning module.
Tables have 1–20 columns and each row must match the header's cell count.
Metadata accepts only `author`, `subject` and `keywords`. Invalid shapes or
invalid UTF-8 return `{:error, :invalid_document}` without including input data.

The fixed A4 layout uses built-in Courier at 10 points, 85 characters per line,
and 48 lines per page. Columns share the available width equally. Text and cells
wrap without truncation, including long words; blank lines are preserved, tabs
become spaces and CR/CRLF become newlines. Table headers repeat after page breaks.
Rows that fit a page stay together; larger rows continue across pages. A header
must leave room for its separator and at least one data line. Explicit breaks
create no empty trailing pages.

Body text supports printable ASCII and Latin-1 U+00A0–U+00FF through the font's
WinAnsi encoding. Unsupported characters and controls return
`{:error, :unsupported_text}`; they are never silently replaced. PDF metadata
supports Unicode. Owners requiring other scripts or richer layouts use the HTML renderer below
or a separately selected renderer behind the same behaviour. Content operands are
escaped and metadata uses hex strings, so text cannot inject PDF instructions.
Identical input produces identical bytes: the serializer adds no timestamps,
random IDs or environment-derived metadata. It never interprets HTML or URLs.

## HTML PDFs and password protection

Implement `Bilimbi.Base.Artifacts.PDF.render_html/4` on the trusted Owner. Return
`{:ok, complete_html_binary}` after selecting the subject's permitted data and
rendering its HEEx template. Use `PDF.render_inline/6` when the template needs
only its supplied scope/data; use `PDF.render_view/6` to execute it inside an
HTTP request through `/pdf/render/:token`. Both receive the original sealed
scope, recheck create authorization before rendering and again at publication,
and return `{:ok, %PDF.Artifact{}}` holding the existing private document metadata.
The HTTP route builds no login session and accepts no template, actor or data
parameters. It checks the live tenant and installed actor verifier, then the
owner's current permission. Unknown, expired, replayed or refused requests
return 404; responses are no-store, noindex and nosniff. Phoenix endpoint and
router logging respect this route's `log: false`. Template failures return a
fixed empty 500 without logging document contents. The render process records
the signed actor and a token-free route pattern in its audit context.

```elixir
alias Bilimbi.Base.Artifacts.PDF
{:ok, artifact} = PDF.render_inline(scope, company_id, DocumentOwner, reference,
  selected_data, template_version: "payslip-v1", data_version: "run-17",
  password: password)
{:ok, %{bytes: bytes}} = Artifacts.read(scope, company_id, DocumentOwner,
  artifact.document.id)
```

Optional passwords protect the bytes before publication, so a queued protected
render never stores an unprotected copy. `PDF.protect_with_password/6` instead
reads an existing PDF through Artifacts and stores a new AES-256 protected copy,
leaving its source unchanged. An omitted owner password uses the user password;
an empty user password is refused by this operation. A protected artifact's data
version gains ` (encrypted)`. `PDF.persist/6` is the writer seam for existing PDF
bytes; it stores through `Artifacts.put/6`, never a second filesystem service.
`PDF.Artifact.to_map/1` returns artifact ID, versions, byte count, digest, producer
and production time. Versions and production time describe this returned value;
the existing artifact table retains the byte lifecycle and audit provenance.

The PDF-only runner uses Node's standard library and Chromium's
[DevTools printToPDF API](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-printToPDF).
It adds no npm/Hex browser dependency and has no AI integration. Install Node.js
22 or newer, a sandbox-capable Chromium and qpdf 10.6 or newer. Configure their
executables in Operator Settings. `PDF.protection_available?/0` checks the
configured Node.js and qpdf executables before offering password protection. Do not disable Chromium's sandbox. Documents
must embed their CSS, images and fonts: scripts, downloads, remote resources,
local file resources and navigation beyond the initial signed URL are blocked.
The HTML route allows embedded styles and data resources through its CSP.
Chromium prints the selected paper size and background option. HTML generation
is for trusted owner templates, never arbitrary user-supplied URLs or templates.

Temporary requests, plaintext inputs, passwords, encrypted output and browser
profiles stay inside random 0700 directories; document and request files use 0600 permissions and are
removed after success, failure or timeout. qpdf uses
[QPDFJob JSON](https://qpdf.readthedocs.io/en/stable/qpdf-job.html) rather than putting
passwords in process arguments. Tool output is discarded, and callers receive
fixed error atoms. Deadlines kill the tool process group, including Chromium
children. A machine/application crash can leave temporary directories: include
`bilimbi-pdf-*` in the host's private temporary-file cleanup policy.

Signed render claims are bounded, short-lived and held only in the issuing
node's memory. A per-boot HMAC is verified before a token is consumed or
revoked, so a forged or altered token is refused and touches no claim. Atomic consumption prevents concurrent replay; expiry timers and
explicit render cleanup erase them. The signed URL is a transient capability,
never a document download token. Set `pdf.render_origin` to the application
origin reachable from Chromium and route `/pdf/render/*` back to the issuing
node. Multi-node deployments need that node affinity; restart discards pending
claims and the caller retries with a fresh URL. Do not log these URL paths at
the application proxy. Inline mode needs no origin or HTTP endpoint.

## Queued rendering and completion

Implement `pdf_request/4` and `pdf_rendered/4` on the trusted Owner. The first
receives the current execution scope, company, document reference and opaque
request ID and returns `{:ok, %{mode: :inline | :view | :document, data: map,
options: keyword, metadata: map}}`. It resolves current authorized data,
versions, passwords and completion routing metadata. `:document` uses the
existing `render_pdf/4` callback; the other modes use `render_html/4`.

`PDF.enqueue(scope, company_id, DocumentOwner, reference, request_id)` authorizes
and uses `Queue.enqueue_for/3`. Only the adapter name, company, subject, kind and
request ID enter Oban; document data, passwords and caller-selected actors are
refused by the worker's exact allowlist. The adapter is selected in trusted
server code. Queue re-proves the user and impersonation before execution, and
the worker rechecks the owner's current create access before selecting data. Actorless legacy jobs do not become privileged system
jobs: `enqueue/5` refuses an anonymous system scope. Scheduled document owners
use their declared system-principal worker and call the synchronous PDF API;
Base PDF does not borrow a user or invent Domain permissions.

On success, `pdf_rendered/4` receives a `%PDF.Rendered{request_id, job_id,
artifact, metadata}` completion fact. It contains no input data or passwords.
No event is delivered for a failed/refused render. Publication failure retries;
permission refusal cancels. Completion handlers must return `:ok` or
`{:error, reason}`. Delivery, including completion callbacks, is at least once,
matching Belimbing's queue; owners use the request ID to enforce their business
idempotency. A failed callback can retry and produce another tracked artifact;
retention still owns cleanup. No payroll or other Domain adopter is wired here.

## PDF port compatibility

Belimbing's `app/Base/Pdf` owns no tables or migrations. Its generated-file
paths, cache tokens, Laravel jobs and Blade views are framework internals;
Bilimbi uses the existing `base_artifacts` table, scoped storage, HEEx callbacks
and Base Queue. No existing table or column is changed by this port. Drain or
disposition Laravel PDF jobs at cutover; never deserialize them into Oban. Old
render URLs expire at cutover. Existing Domain records containing legacy
`disk`/`path` PDF metadata remain unchanged: the Domain that adopts their document
workflow must provide its explicit legacy-file bridge, rather than Base
inventing an unscoped importer. This port does not migrate Domain documents.

## Operator settings and storage

All settings appear in the existing **Operator Settings** screen at
`/system/settings`. Access requires `base.settings.global.manage` for the page
and `admin.system.artifacts.manage` for these fields. These are installation
settings; documents and retention operations remain tenant/company scoped.

| Key | Meaning |
| --- | --- |
| `pdf.node_binary` | Node.js executable; default `node`. |
| `pdf.chromium.binary` | Chromium executable; default `chromium`. |
| `pdf.qpdf.binary` | qpdf executable; default `qpdf`. |
| `pdf.render_origin` | Issuing node's reachable application origin; initially empty. |
| `pdf.signed_url_ttl_seconds` | Single-use render token expiry; default 60, range 1–600 seconds. |
| `pdf.max_render_tokens` | Pending render claims per node; default 100. |
| `pdf.render_timeout_seconds` | Chromium deadline; default 30, range 1–600 seconds. |
| `pdf.qpdf.timeout_seconds` | qpdf deadline; default 60, range 1–600 seconds. |
| `pdf.paper.format` | A4 (default), A3, A5, Letter, Legal or Tabloid. |
| `pdf.paper.print_background` | Print background graphics; default true. |
| `artifacts.storage_root` | Existing absolute private directory; initially empty, so storage is disabled. |
| `artifacts.retention_days` | Required positive period; initially unset. Expiry is captured at creation. Changes affect new documents. |
| `artifacts.max_bytes` | Maximum uploaded/generated size; safety default 10 MiB. |
| `artifacts.purge_batch_size` | Maximum records considered per owner/company maintenance call; default 100. |
| `artifacts.purge_retry_minutes` | Wait before retention retries a failed or refused purge; default 60. |
| `artifacts.purge_max_attempts` | Failed or refused purges before a document is held for an operator; default 5. |

Provision the root with mode `0700` for the application OS account. Files use
random UUID names and mode `0600`. Base rejects relative roots, symlink path
components, public/static/assets directories and permissive directory modes.
The root and parents must be controlled by trusted operators. Never serve this
root through Phoenix, a proxy, a CDN or another application. Permission checks
do not administer web server configuration. Encryption at rest and backup
access follow deployment policy; the OS account and operators are trusted.

Use a durable volume shared by application nodes handling these documents.
Back up metadata and that volume together. A root change affects new documents
only: existing records retain their original location for reads and cleanup.
Preserve old roots until their records are physically purged. Changing the root
does not move files.

## Retention and recovery

`purge_expired(scope, company_id, DocumentOwner)` considers an ordered, bounded
batch of that owner's company records. It first authorizes `:purge` with a nil
reference before selecting candidate IDs, then rechecks delete access for every
candidate. It returns `{:ok, %{deleted: ids, errors: [{id, reason}]}}`. The owning
module wires this into its authorized scheduled maintenance workflow with its
declared system principal and operator-controlled schedule. Base does not
enumerate arbitrary companies. Monitor errors in that calling workflow.

Expiry refuses reads immediately, even before maintenance runs. An ordinary
document has no implied legal hold. The owner resolves its retention
obligations before storage; an unset period refuses uploads. The owner must
authorize retention deletion appropriately. A document that must outlive the
operator period is records-grade (next section).

## Records-grade retention

Original source documents a law requires the business to keep (bank statement
files, supplier invoice scans, contracts) are stored with a retain-until date
instead of an expiry. The owner derives the date from its own obligation and
settings; Base never guesses a period.

```elixir
{:ok, document} =
  Artifacts.put(scope, company_id, DocumentOwner, reference, bytes, content_type,
    retain_until: retain_until, legal_hold: false, reason: "Income Tax Act 1967 s.82")

{:ok, document} = Artifacts.retain(scope, company_id, DocumentOwner, id, later_date)
{:ok, document} = Artifacts.place_hold(scope, company_id, DocumentOwner, id, reason: "case 12")
{:ok, document} = Artifacts.release_hold(scope, company_id, DocumentOwner, id)
{:ok, events} = Artifacts.retention_history(scope, company_id, DocumentOwner, id)
```

A records-grade document never expires: `expires_at` is nil, reads keep
working until retain-until and after, and `purge_expired/3` never selects it.
`delete/4` answers `{:error, :legal_hold}` while a hold stands and
`{:error, :retained}` before retain-until; after retain-until an explicit,
`:delete`-authorized call deletes it, and nothing deletes it automatically.
`retain/6` makes an ordinary document records-grade (its expiry is gone for
good) or moves retain-until later; an equal or earlier date is
`{:error, :retention_not_extended}`, and a date that is not in the future is
`{:error, :invalid_retention}`. A legal hold needs a retained document
(`{:error, :not_retained}`); placing one twice is `{:error, :already_on_hold}`
and releasing one that is not there is `{:error, :not_on_hold}`. Retention at
creation is applied in the publication transaction, so a failed upload stays
an ordinary reservation that cleanup can tombstone. The operator period still
governs reservations and ordinary documents.

The owner authorizes `:retain` for every retention change, on top of
`:create` at creation. Retention is irreversible, so grant it to the people
the business trusts with that commitment; `:read` is enough for the history.

The database guards the same rules behind the facade
(`base_artifacts_retention_guard`): a retained row's `retain_until` cannot be
cleared or moved earlier, and its `deleted_at`, `purged_at` or row cannot be
deleted while on hold or before retain-until, from any client. Two checks
keep the states exclusive: exactly one of `expires_at` and `retain_until` is
set, and a hold needs `retain_until`. The schema contract verifies the
triggers are installed and enabled.

Every change writes one row to `base_artifact_retention_events`: the event
(`retained`, `retention_extended`, `hold_placed`, `hold_released`), the
retain-until and hold state after it, the optional reason (at most 255
characters; never document content), the scope actor (user, guest or system
principal, with any impersonator) and `recorded_at`, which PostgreSQL stamps
in the append-only trigger; the application cannot supply it, and updates,
deletes and truncates of that table are refused. The same change also records
an `artifacts.<event>` audit action, like every other artifact operation, and
is refused when the audit log is unavailable. `retention_history/4` returns
the events, oldest first, for any document the caller may read, tombstones
included.

A failed or refused purge records its attempt count, last error and attempt
time, and records `artifacts.purge_failed`. Retention skips that document until
the retry interval passes, so later expired documents are always reached. After
the maximum attempts it records `artifacts.purge_held` and the batch excludes it.
`list_purge_holds(scope, company_id, DocumentOwner)` lists held documents with
their reason and attempts for the owner's operator workflow.
`retry_purge/4` releases a hold (`artifacts.purge_released`) and purges now,
rechecking delete access. `resolve_purge/4` records `artifacts.purge_resolved`
for bytes an operator removed out of band and refuses while the file exists.
All three require `:purge` authorization.

A committed reservation precedes file creation. It stays unreadable until the
file is complete, synced and publication is authorized. Creation holds the
reservation lock so maintenance cannot purge a reservation before its writer
creates the file. Interrupted reservations
expire through the same retention path, keeping every file tracked. Failed
uploads are tombstoned for cleanup.

Deletion commits an audited tombstone before removing bytes. The document is
then inaccessible. Physical removal is idempotent; an unavailable filesystem
leaves a tombstone for maintenance to retry. Physical purge is successful only
when `:deleted` is returned. Metadata remains as a provenance tombstone; its
removal is outside this byte-retention contract.

Reads lock metadata, reauthorize, check expiry (a records-grade document has
none) and SHA-256 integrity, then record `artifacts.read` before returning
bytes. Deletes record `artifacts.delete` and physical cleanup records
`artifacts.purge`. Actions carry tenant/company, scope actor attribution,
artifact ID and stable owner ID. Metadata writes also receive standard Repo
mutation capture. Denied/failed reads return no bytes.

## Schema and verification

The descriptor owns the Bilimbi-only migrations and schema contract for
`base_artifacts` and `base_artifact_retention_events`. Incoming compatible
databases may lack this Bilimbi-only contribution until migration; the owner
invariant checks its complete structure whenever present, guard triggers
included, and rejects partial installation or drift. Tenant identity has a
restricted foreign key; company identity has a PostgreSQL positivity check and
the owning-module validation contract.
Run `mix bilimbi.migrate` from the umbrella root. Focused tests run with
`cd apps/base/artifacts && mix test`, using module-owned temporary tables and
the shared SQL sandbox.

Backend tests cover the writer, protection, queue privacy/completion, token
concurrency/expiry and the real host render route. Executable fixtures exercise
failure and timeout deterministically without requiring OS tools in CI. Run
real tool tests after installing Chromium and qpdf:

```bash
PDF_TEST_CHROMIUM=/usr/bin/google-chrome PDF_TEST_QPDF=/usr/bin/qpdf \
  MIX_TEST_PARTITION=_pdf mix test --include pdf_tools
```
