# Base Media

`Bilimbi.Base.Media` owns Belimbing's `base_media_assets` and
`base_media_attachments`. Its compatible baseline keeps the original names,
bigserial IDs, nullable second-precision timestamps, JSON metadata, `char(26)`
attachment ULIDs, named foreign keys, indexes, and table unique constraints.
Adoption retains existing asset paths, subject aliases, and draft/submitted
values. Compatibility's Laravel-generated fixture already contains these tables.

Use Media for stored uploads, asset derivatives, and private subject attachments.
Use `Bilimbi.Base.Artifacts.generate_pdf/5` with `Artifacts.PDF` for generated
private PDFs, and `Artifacts.PDF.Renderer` for simple text/table documents. The
Artifacts lifecycle remains separately owned; Media does not duplicate its
serializer, expiry, integrity checks, or owner contract.

## Storage and trusted asset APIs

Configure **Administration → Settings → Operator** before accepting uploads:

- `media.disks`: a map from durable disk names (for example `local`) to existing
  absolute private local directories with permissions `0700`. Map adopted disks
  to their existing contents; leave roots stable while assets reference them.
  Remote/cloud filesystem adapters are outside this local implementation.
- `media.attachment_disk`: the disk for new private attachments, default `local`.
- `media.max_bytes`: upload size limit, default 10 MiB.
- `media.attachment_allowed_types`: detected MIME allowlist for private uploads.
- `media.stream_ttl_seconds`: signed asset link lifetime, default five minutes.

The host needs the `file` executable and its libmagic MIME database. Upload
validation examines the server-side temporary file, ignoring the browser's MIME
claim and filename extension. HTML, XML and SVG uploads are always refused.
Uploads return a clear error when detection is unavailable. There is no new Hex
dependency: libmagic supplies the same content-based detection the source uses.

`put_upload(scope, disk, directory, %Plug.Upload{}, metadata)` assigns a random
key under `tenants/{id}/{directory}` and returns asset metadata without private
paths. `put_derivative_bytes(parent_id, kind, disk, key, bytes, attrs)` stores a
new derivative. `store_original/3` and `store_derivative/5` register bytes an
authorized owner already produced on a configured disk. These are trusted owner
APIs, not controller actions; the caller owns business authorization. Asset rows
have no tenant column in the compatible schema. Their summary, derivatives,
signed URL, and deletion APIs preserve that contract rather than inventing one.

`display_url(id, signing_context)` returns a safe HTTP(S) URL from
`metadata.public_url` for the `external` sentinel disk, otherwise a signed stream
path. `stream_url/2` uses the host endpoint or its secret as signing context. The
signed link authorizes one asset for its issued lifetime; it is deliberately
separate from private evidence downloads. Only JPEG, PNG, GIF and WebP render
inline. Other assets download as octet-stream. Responses carry `nosniff`, a
restrictive sandbox CSP and private/no-store caching. Filename headers are encoded.

Generic streaming, derivatives and deletion refuse assets bound to private
attachments, including an ancestor or descendant of such an asset. Asset row
and key inputs never become module names, executable commands, or shell text.
Storage rejects traversal, public/static/assets roots and symlinks. New files
are exclusive and `0600`; adopted regular files remain readable.

## Private subject attachments

The subject owner depends on `base/media` and contributes:

```elixir
%{media: %{subjects: [%{
  key: "orders.order",
  aliases: ["App\\Domains\\Orders\\Models\\Order"],
  adapter: MyDomain.OrderAttachments
}]}}
```

The adapter implements `Bilimbi.Base.Media.AttachmentSubjectAuthorizer`.
`authorize(scope, action, subject_id, attachments)` resolves the live subject
through its owner's public API and checks the action capability with the given
scope. Return `:ok` or `{:error, reason}`; missing/deleted or cross-tenant subjects
must fail. Media looks up the exact stable key or legacy alias on every operation.
Descriptor provenance verifies the adapter belongs to its contributing package;
duplicate keys/aliases and missing dependencies fail at snapshot installation.
An unknown subject has no access. No optional business domain is wired here.

- `upload_attachment(scope, {type, id}, upload)` validates, authorizes, writes
  private bytes, and creates a draft naming the sealed scope user.
  An optional fourth map with `:max_bytes` and `:allowed_mime_types` lets the
  subject owner narrow its rules within the operator's upload limits.
- `submit_attachments(scope, subject, public_ids)` deduplicates IDs, locks all
  scoped rows in stable order, authorizes submit, validates the complete subject
  match, and atomically marks them submitted. Repeated submission is idempotent.
- `retain_drafts/3` uses the same locking and subject policy; retained drafts
  survive abandoned-draft cleanup. Submitted references remain unchanged.
- `download_attachment/2` rechecks the subject's download policy each time.
  `/media/attachments/:public_id` additionally requires a live host session.
- `discard_draft/2` allows only the uploader to discard a current-tenant draft.
  Submitted references have no deletion or mutation operation.

These operations refuse system actors. Impersonated actors are refused because
the compatible attachment row has no impersonator field. The submitted reference
is immutable through this API; PostgreSQL's asset FK also restricts deleting its
bytes through an asset-row cascade. All row writes pass through the audited Repo.
Scope operations attribute mutations to the sealed user or maintenance actor.

Submit and retain may compose inside the owner's business transaction; rollback
rolls back evidence binding. Upload, discard and asset file operations require
an outer transaction to have committed. Failed upload registration removes the
new file. As in Belimbing, deletion commits rows before removing their files so
rollback cannot strand live references. A filesystem cleanup failure reports
`:cleanup_failed`; operators must reconcile remaining files on their disk. This
port does not introduce a separate storage job ledger.

## Maintenance

From the complete umbrella runtime:

```bash
mix bilimbi.media.attachments.cleanup --tenant 41 --hours 24
```

The command requires one explicit tenant and a positive age. It calls
`cleanup_drafts_before(scope, cutoff)` and locks/rechecks each candidate before
discarding it. Submitted, retained, newer, and other-tenant rows are untouched.
There is no automatic schedule, matching Belimbing's Base Media wiring.

## Deferred scope

Photo cleanup is entirely deferred behind the owner's AI hold. This includes
the lifecycle, provider seam, PhotoRoom/Poof clients, credential resolution,
selection and AI family registration. No partial cleanup capability is claimed.
Full Base Pdf browser rendering, signed render tokens, queued rendering and
password protection are separate from this Media port and the existing simple
Artifacts renderer.
