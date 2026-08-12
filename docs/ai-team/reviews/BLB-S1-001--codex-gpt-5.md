# BLB-S1-001 Review — codex/gpt-5

**Reviewer:** codex/gpt-5
**Role:** Independent architecture and compatibility reviewer
**Reviewed Commit/Diff:** Worktree changes above baseline `54b50b0`, limited to `apps/core/geonames/**`
**Task Card:** [BLB-S1-001](../tasks/BLB-S1-001.md)
**Date:** 2026-08-12

## Verdict

`changes required`

## Findings

### Critical

None.

### Major

1. `apps/core/geonames/lib/geonames/importer.ex:62-84` treats a readable file with zero valid country, admin1, or city rows as a successful import. `apps/core/geonames/lib/geonames/downloader.ex:53-58` has already promoted the downloaded payload into the cache before that validation can occur. A truncated file, HTML error body returned with status 200, or upstream format change can therefore replace the last good cache and make `mix bilimbi.geonames.import --datasets countries` report success with `imported: 0`. Postcodes explicitly reject this state, but the three default datasets do not. Reject empty/implausible default datasets and arrange validation so an invalid payload cannot replace the known-good cache; add focused tests for each dataset class.

2. `apps/core/geonames/lib/geonames/importer.ex:62-81` invokes each batch persistence function without converting Ecto/Postgrex failures into the tagged error contract promised by `Bilimbi.Core.Geonames.import_reference_data/1`. Earlier batches remain committed, while a later unique/FK/database error escapes as an exception rather than `{:error, {:import, dataset, reason}}`; the Mix task consequently emits a raw crash instead of its declared operational failure. Define the intended partial-progress/transaction policy, normalize database failures at the module boundary, and test a failure after at least one successful batch.

### Minor

1. `apps/core/geonames/lib/geonames/downloader.ex:32-34` is not formatted. Independent `mix format --check-formatted` fails on the missing separator after the `stored_etag` assignment, contrary to the handoff's formatting claim.

2. `apps/core/geonames/lib/geonames/reference_data.ex:47-54` passes the public option list through to internal downloader/importer seams, and `apps/core/geonames/lib/geonames/importer.ex:33` accepts a caller-selected `:repo`. Tests exercise downloader injection through the public facade. This makes a production API that is documented as one canonical operation also expose test plumbing and an alternate-Repo escape hatch, weakening the one-shared-Repo/deep-module contract. Whitelist supported public options and keep dependency injection behind an internal entry point.

## Acceptance-criteria check

- [ ] Public contract
- [x] Module/dependency boundaries
- [x] Belimbing schema/data compatibility
- [x] Tenant, authorization, and soft-delete behavior where relevant (global reference data; no tenant scope applies)
- [ ] Failure paths and operational observability
- [ ] Focused tests and documentation
- [x] No unrelated or unclaimed changes

## Validation independently performed

- Read the GeoNames migrations, models, seeders, downloader, and postcode job in canonical Belimbing commit `e70b4d33c0b10790e681f4c2b5095d85a53bc918`.
- Inspected the complete GeoNames worktree implementation, descriptor, migration/schema contract, tests, and module documentation.
- Ran `mix test` from `apps/core/geonames`: 15 passed.
- Ran `mix format --check-formatted` from `apps/core/geonames`: failed for `lib/geonames/downloader.ex`.

## Follow-up tasks suggested

- Add the shared reference/bootstrap ledger identified by the S1 source inventory so runs and failures remain observable after the Mix process exits. This belongs to Base Database/integration, not this module-only fix.
