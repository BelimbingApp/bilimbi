# Core User

**Stable module ID:** `core/user`
**Layer:** Core · required
**Canonical source:** Belimbing `app/Core/User`, migration prefix `0200_01_20_*`

Owns user accounts and their affiliation to a company and an employee record.
Authentication is deliberately **not** here — see [Deferred](#deferred).

## Public API

Every function takes a `Bilimbi.Base.Tenancy.Scope`. Ecto schemas, queries, and
the stored credential never leave the module; reads return
`Bilimbi.Core.User.Summary`.

| Function | Purpose |
|---|---|
| `list_company_users(scope, company_id)` | Users affiliated with one proven company |
| `get_user(scope, company_id, user_id)` | One user inside that company |
| `create_user(scope, company_id, attributes)` | Create; requires `:password_hash` |
| `update_user(scope, company_id, user_id, attributes)` | Update |
| `delete_user(scope, company_id, user_id)` | Hard delete — `users` has no soft delete |
| `notifiable_identity()` | The durable Laravel polymorphic string |

## Tables

Five, reproducing the canonical shape exactly.

| Table | Notes |
|---|---|
| `users` | No `tenant_id`, no soft delete, nullable `company_id` and `employee_id` |
| `password_reset_tokens` | Primary key is the email address; no FK to `users` |
| `user_pins` | `url_hash` is `char(32)`, an MD5 backing `(user_id, url_hash)` |
| `user_database_queries` | User-owned SQL pages, unique per `(user_id, slug)` |
| `notifications` | **uuid** primary key; polymorphic `notifiable`, no FK |

The migration also completes the `core/user external-access owner` optional
group that Core Company declares — `company_external_accesses.user_id`, its
`(user_id, is_active)` index, and the foreign key. All three land together
because the verifier reports a partly-present optional group as an incomplete
contribution.

## Design notes

**Tenancy is derived, not stored.** `users` has no `tenant_id`. A user reaches
a tenant only through its nullable `company_id`. Belimbing's own list
(`app/Core/User/Livewire/Users/Index.php:110-111`) left-joins `companies` and
filters `companies.tenant_id`; because the `WHERE` lands on the right-side
table, a user with no company is invisible to every tenant-scoped read. This
module gets the same visibility by resolving the company through
`Bilimbi.Core.Company.get_company/2` first, so it never touches Company's
tables.

**This module stores credentials; it never creates them.** `users.password` is
non-null and holds Laravel bcrypt output — a crypt-format string. Bilimbi has
no hashing dependency and S1 deliberately does not add one, so writes take an
already-hashed `:password_hash` and reject anything that is not crypt-format,
rather than silently storing a plaintext password. `Summary` has no `password`
or `remember_token` field by construction, not by filtering.

**Employee affiliation is checked through Core Employee's API**, never by
querying `employees`. A foreign key to another module's table does not grant
read access to its schema.

**`users.prefs` is intentionally absent.** Belimbing dropped it in
`0200_01_20_000007`, moving four keys into `base_settings` under
`scope_type: 'user'`. Porting it would resurrect a deleted column.

## Deferred

Registration, login, sessions, password-reset flow, email verification,
authorization, and user preferences belong to S2 with Base Authz, Base
Settings, and Session. `user_pins` and `user_database_queries` have schema but
no public API: they are UI features owned by Menu and the Base Database query
surface in S3. `User::getLastUsedModel()` is Core AI's, in S4.
