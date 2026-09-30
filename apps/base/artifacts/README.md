# Base Artifacts

`base/artifacts` stores sensitive uploaded and generated business documents.
Domain modules use `Bilimbi.Base.Artifacts` rather than exposing private files.
This slice provides private storage and a PDF generation contract, with no media
browser, public URLs, reusable access tokens or document business workflows.

## Owning-module integration

Declare a descriptor dependency on `base/artifacts`. Implement the
`Bilimbi.Base.Artifacts.Owner` behaviour in a trusted server-selected adapter:

- `artifact_owner_id/0` returns the business module's stable logical ID.
- `authorize(scope, company_id, operation, reference)` returns literal `:ok`
  only when the company is live, belongs to the tenant scope, and the current
  scope actor may perform `:create`, `:read` or `:delete` on that business subject. For `:purge`,
  the reference is nil and the check must grant company maintenance access.
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

Metadata contains ID, subject, kind, content type, byte size, SHA-256 and expiry;
it exposes no Ecto schema or storage path. MIME type is owner-supplied metadata,
not a content safety claim. The owner validates accepted uploads and any needed
scanning/quarantine before storage. Its authenticated download adapter calls
`read/4` on every request and delivers an attachment with private/no-store cache
headers and content sniffing disabled. Never cache bytes for later callers.

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
This slice selects no rendering engine, executable command, external service or
business template. Renderers must not fetch untrusted resources or log contents.

## Operator settings and storage

All settings appear in the existing **Operator Settings** screen at
`/system/settings`. Access requires `base.settings.global.manage` for the page
and `admin.system.artifacts.manage` for these fields. These are installation
settings; documents and retention operations remain tenant/company scoped.

| Key | Meaning |
| --- | --- |
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

Expiry refuses reads immediately, even before maintenance runs. There is no
unbounded retention or implied legal hold. The owner resolves its retention
obligations before storage; an unset period refuses uploads. The owner must
authorize retention deletion appropriately.

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

Reads lock metadata, reauthorize, check expiry and SHA-256 integrity, then record
`artifacts.read` before returning bytes. Deletes record `artifacts.delete` and
physical cleanup records `artifacts.purge`. Actions carry tenant/company, scope
actor attribution, artifact ID and stable owner ID. Metadata writes also receive
standard Repo mutation capture. Denied/failed reads return no bytes.

## Schema and verification

The descriptor owns the Bilimbi-only migration and schema contract for
`base_artifacts`. Incoming compatible databases may lack this Bilimbi-only
contribution until migration; the owner invariant checks its complete structure
whenever present and rejects partial installation or drift. Tenant identity has a restricted foreign key; company identity
has a PostgreSQL positivity check and the owning-module validation contract.
Run `mix bilimbi.migrate` from the umbrella root. Focused tests run with
`cd apps/base/artifacts && mix test`, using module-owned temporary tables and
the shared SQL sandbox.
