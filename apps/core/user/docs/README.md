# Core User

**Stable module ID:** `core/user`
**Layer:** Core · required
**Canonical source:** Belimbing `app/Core/User`, migration prefix `0200_01_20_*`

Owns user accounts, credentials, email verification, password-reset state, and
the four user-scoped preferences moved out of Belimbing's deleted `users.prefs`
column. It also owns affiliation to a company and an employee record.

## Public API

Tenant-owned functions take a `Bilimbi.Base.Tenancy.Scope`. Login and reset
lookup deliberately use the globally unique email because no tenant scope
exists before authentication. Ecto schemas, password hashes, remember tokens,
and reset-token hashes never leave the module; account reads return
`Bilimbi.Core.User.Summary`.

| Function | Purpose |
|---|---|
| `list_company_users(scope, company_id)` | Users affiliated with one proven live company |
| `list_users(scope)` | Tenant-wide list; includes users of soft-deleted companies |
| `get_user(scope, company_id, user_id)` | One user inside that company |
| `register_user(scope, company_id, attributes)` | Create an unverified account from plaintext `:password` |
| `create_user(scope, company_id, attributes)` | Compatibility name for `register_user/3` |
| `update_user(scope, company_id, user_id, attributes)` | Update |
| `delete_user(scope, company_id, user_id)` | Hard delete — `users` has no soft delete |
| `list_unaffiliated_users(actor, scope)` | Operator-only list of users without company affiliation (`admin.user.unaffiliated.manage`) |
| `get_unaffiliated_user(actor, scope, user_id)` | Operator-only read of one unaffiliated user |
| `create_unaffiliated_user(actor, scope, attributes)` | Operator-only creation of an unaffiliated user account |
| `assign_unaffiliated_user(actor, scope, user_id, target_company_id, opts)` | Assign an unaffiliated user to a live company and optional employee |
| `reassign_user_company(actor, scope, current_company_id, user_id, target_company_id, opts)` | Reassign a user to a target live company with ascending lock ordering |
| `clear_user_company(actor, scope, current_company_id, user_id, opts)` | Move an affiliated user back to unaffiliated state |
| `admin_change_password(actor, scope, company_id, user_id, new_password, opts)` | Admin password reset with token rotation and session invalidation |
| `authenticate(email, password)` | Verify a login and upgrade legacy bcrypt |
| `confirm_password(...)` / `change_password(...)` | Current-password confirmation and replacement |
| `request_password_reset(email, deliver_fun)` | Neutral, throttled request; callback receives the one plaintext token |
| `reset_password(email, token, password)` | Consume a 60-minute token and rotate `remember_token` |
| `issue_email_verification_token(...)` / `verify_email(...)` | Signed 60-minute verification bound to the current email |
| `user_preferences(...)` and preference get/put/delete | Scoped access to the four module-owned settings |
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
module gets the same visibility by resolving companies through Core Company's
public API (`get_company/2` for single-company reads;
`list_tenant_company_ids/1` for the tenant-wide list), so it never touches
Company's tables. Soft-deleted companies stay visible in `list_users/1` to
match Belimbing (BLB-S1-010 option a).

**Credential creation belongs to the module.** Callers provide plaintext only
under `:password`; `:password_hash` is not a public input. New credentials and
reset tokens use Argon2id. Existing Laravel Argon2 hashes verify directly.
Laravel's legacy bcrypt prefix `$2y$` is normalized to the equivalent `$2b$`
only while verifying, then a successful login replaces that hash with
Argon2id. Missing accounts perform dummy verification, and login/reset failures
do not reveal whether an email exists. `Summary` has no credential or remember
token field by construction.

**Account creation is not public registration.** Belimbing deliberately has no
`/register` route. `register_user/3` is the trusted administrative primitive;
the future Web adapter must gate it with the normal Authz capability. New
accounts start unverified. Changing an email clears its verification timestamp.

**Reset and verification delivery remain adapters.** Core User stores the
hashed reset token, while a caller-provided delivery function receives the
safe account summary and one plaintext token. Email verification uses
`Plug.Crypto` signing with a caller-provided secret of at least 32 bytes; Web
owns the eventual URL and mail templates. Web also owns request/IP rate
limiting, session cookies, and Phoenix navigation.

**Employee affiliation is checked through Core Employee's API**, never by
querying `employees`. A foreign key to another module's table does not grant
read access to its schema.

**`users.prefs` remains intentionally absent.** Belimbing dropped it in
`0200_01_20_000007`. Core User contributes and validates `ui.theme`,
`ui.landing_menu_id`, `ui.dashboard.layout`, and
`ai.last_used_model_hints`; Base Settings persists their overrides under
`scope_type: 'user'`.

## Deferred

Phoenix routes, forms, mail delivery, login throttling, and the authenticated
Session adapter remain a Web slice. `user_pins` and `user_database_queries`
have schema but no public API: they are UI features owned by Menu and the Base
Database query surface in S3. `User::getLastUsedModel()` is Core AI's, in S4.
