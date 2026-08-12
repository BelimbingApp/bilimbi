# BLB-S1-002 Review — amp/kimi-k3

**Reviewer:** amp/kimi-k3
**Role:** Independent reviewer (source-analysis and compatibility)
**Reviewed Commit/Diff:** `docs/ai-team/research/platform-baseline-inventory.md`
as handed off (amended) at 2026-08-12T20:44+08, landed via PR #5
**Task Card:** [BLB-S1-002](../tasks/BLB-S1-002.md)
**Date:** 2026-08-12

## Verdict

`accept with follow-up`

The inventory is evidence-dense and survived independent re-verification of
its load-bearing citations. Two minor corrections are requested; neither
changes a recommendation.

## Findings

### Critical

None.

### Major

None.

### Minor

1. **§7.1 (and the repeated claim in the original CLAIM): "inner join" is
   not what Belimbing does.** `app/Core/User/Livewire/Users/Index.php:110-111`
   uses `leftJoin('companies', …)` plus
   `where('companies.tenant_id', …)`. The behavioral conclusion is correct —
   the `WHERE` on the right-side table filters null-`company_id` users, so
   they are invisible to tenant-scoped lists — but the port should reproduce
   the actual mechanism (left join + tenant filter), and the wording matters
   because BLB-S1-006's card quoted it. Fix the wording in §7.1; the steward
   has corrected the BLB-S1-006 card in the same commit as this review.
2. **§4.1 understates the Authz optional group.** The Core/Company migration
   `0200_01_07_001007_scope_custom_authz_roles.php` installs not only the
   `base_authz_roles_company_foreign` FK and the
   `base_authz_roles_custom_company_check` constraint but also insert/update
   **triggers** (`base_authz_roles_custom_company_insert/update`). When the
   Authz contract task is created from §9, its optional group must include
   the triggers or verification will report an incomplete contribution. No
   correction to the inventory's mechanism description is needed — just name
   the triggers when §4.1's last paragraph is turned into a task.

## Acceptance-criteria check

- [x] Every recommendation cites concrete Belimbing paths or behavior —
  re-verified independently (see below).
- [x] Schema and runtime dependencies are distinguished (§4 vs §5).
- [x] Required Platform Baseline work is separated from optional Domains and
  Extensions (§3.1/§3.2 vs §3.3/§3.4).
- [x] No product files, root docs, ADRs, descriptors, migrations, or
  lockfiles were changed by this task.
- [x] The output is usable to split independent, non-overlapping contract
  tasks — already demonstrated: BLB-S1-006/007/008/009 were registered from
  it without a path conflict.

## Validation independently performed

Against `/home/kiat/repo/laravel/blb` at `e70b4d33` (verified
`git log -1` reads the explicit-tenancy merge):

- **§2 prefix/table ledger:** `Schema::create` counts per module match the
  table exactly — Base/Database 12, Base/Settings 1, Base/Workflow 11,
  Core/Company 8, Core/User 5, Core/AI 18; prefixes match
  (`0100_01_25_*` Tenancy through `0200_02_01_*` AI).
- **§4 FK graph:** `users.{company_id,employee_id}` nullable +
  `nullOnDelete` (`0200_01_20_000000`); `company_external_accesses.user_id`
  column+FK+`(user_id,is_active)` index added by Core/User
  `0200_01_20_000002`; `company_departments.head_id` FK added by
  Core/Employee `0200_01_09_000001`; Authz FK/check/triggers added by
  Core/Company `0200_01_07_001007` (see finding 2).
- **§4.3 soft deletes:** `softDeletes` appears in exactly the five claimed
  tables' migrations (tenants, companies, company_relationships,
  company_external_accesses, addresses); absent from Employee and User.
- **§6 seeder ledger:** `base_database_seeders` columns match
  (`seeder_class` unique, `module_name`, `status` default `pending`,
  `ran_at`, `error_message`); `RegistersSeeders` usage confirmed via
  `unregisterSeeder` in `0200_01_09_000002`'s `down()`.
- **§5.2 config discovery:** Base+Core counts are exactly 22 `menu.php`,
  22 `authz.php`, 12 `settings.php` (repo-wide counts including
  Domains/Extensions are 42/38/17 — the inventory's scoping is correct).
- **§7.1/§8.7 type evidence:** `notifications.id` is `$table->uuid('id')`
  with the "breaks every insert" comment; `user_pins.url_hash` is
  `char(32)` with the `(user_id, url_hash)` unique; audit actor columns
  include `$table->ipAddress('ip_address')`
  (`DefinesAuditActorColumns.php:15`) → `inet`; audit mutations/actions use
  `jsonb`.
- **§8.7 verifier claim:** HEAD (`54b50b0`) `schema_verifier.ex` has exactly
  eleven `type_matches?/2` clauses and no catch-all — accurate. Note for
  readers: BLB-S1-007 is in flight in the worktree as this review is
  written; the section describes pre-007 HEAD by design.
- **§8.5 doc discrepancy:** confirmed —
  `docs/architecture/user-employee-company.md` line 75 lists
  `user_id (nullable)` under Employee while the schema has the FK on
  `users`. Migrations are canonical.
- **Bilimbi-side citations:** the `core/user external-access owner`
  optional group exists in `apps/core/company/lib/company/schema_contract.ex`
  (lines 259-277); the in-flight Employee baseline adds
  `company_departments_head_id_foreign` (migration line 57);
  `addressable_identity/0` is at `company.ex:72`; `mix.lock` contains no
  bcrypt/argon2/pbkdf2 package.
- **§3.3 Base/Database size:** 255 PHP files, 106 under `Services/` —
  exact.

## Follow-up tasks suggested

- Author applies finding 1's wording fix to §7.1 (one-sentence edit to the
  research file, still under its claim), after which the steward closes
  BLB-S1-002 as done. No re-review needed for a wording correction.
- When §9's Authz task is created, its card must name the two triggers from
  finding 2.
