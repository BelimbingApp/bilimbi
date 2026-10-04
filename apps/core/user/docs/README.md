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
| `dashboard_summary(scope)` | Total/verified/unverified counts plus the first five accounts by ID; same tenant visibility as `list_users/1`, with credentials excluded from the query |
| `get_user(scope, company_id, user_id)` | One user inside that company |
| `register_user(scope, company_id, attributes)` | Create an unverified account from plaintext `:password` |
| `create_user(scope, company_id, attributes)` | Compatibility name for `register_user/3` |
| `update_user(scope, company_id, user_id, attributes)` | Update |
| `delete_user(scope, company_id, user_id)` | Hard delete — `users` has no soft delete. A person must hold `admin.user.delete` when the call runs; `delete_user/3` owns that check |
| `reassign_user_company(scope, current_company_id, user_id, target_company_id, opts)` | Reassign a user to a target live company with ascending lock ordering. The scope's signed-in user must hold `admin.user.update` in the account's current company, which need not be the company they signed in at (`Authz.can_in_company/5`) |
| `admin_change_password(scope, company_id, user_id, new_password, opts)` | Admin password reset with token rotation and session invalidation. Authorized like `reassign_user_company/5` |
| `authenticate(email, password)` | Verify a login and upgrade legacy bcrypt |
| `confirm_password(...)` / `update_password(...)` | Current-password confirmation and replacement |
| `request_password_reset(email, deliver_fun)` | Neutral, throttled request; callback receives the one plaintext token |
| `reset_password(email, token, password)` | Consume a 60-minute token and rotate `remember_token` |
| `issue_email_verification_token(...)` / `verify_email(...)` | Signed 60-minute verification bound to the current email |
| `user_preferences/1` and preference get/put/delete | The signed-in account's module-owned settings. The scope's actor names the user |
| `DisplayPreferences.presentation/1`, `refresh/1`, `save/3` | The signed-in account's theme, timestamp display, locale, and language — one resolved snapshot per request, one durable write, refused for a session impersonating another account |
| `notifiable_identity()` | The durable Laravel polymorphic string |

`list_user_pins/1`, `toggle_user_pin/2`, and `reorder_user_pins/2` take the
signed-in scope. The Web shell's pin API uses them. A list is allowed while
impersonating; toggle and reorder return `{:error, :impersonating}`. Saved
database queries use the same scope: it names the owner. Notification list,
count, read, and delete for the signed-in user do the same.
`send_notification/3` still names the recipient.

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

Bilimbi also adds Bilimbi-only indexes on `users.company_id` and
`users.employee_id`. Belimbing's PostgreSQL schema lacks them, so the schema
contract treats those indexes as optional during adoption while normal Bilimbi
migration installs them for fresh and adopted databases.

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
the `/users/new` form calls it through its alias `create_user/3` and gates it with the
normal Authz capability. New
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

**The detail page is read-first.** `/users/:id` shows the account as facts.
An operator holding `admin.user.update` edits the name and email in place
through `<.inline_edit>` and changes the company through a choice that reads
as the company name and becomes a select on click; every commit saves by
itself and reports on its own fact, so there is no "Edit user" button and no
edit mode to reach from the page. The select offers the workspace's live
companies and nothing else. A user always belongs to a company and is the
same person operating under a different one, so the page never detaches an
account: Belimbing's select offers "None" and Bilimbi's does not, and a
blank value that still arrives is refused on the fact without a write. The
reassignment ends the account's sessions — `reassign_user_company/5` calls
`Session.terminate_user_sessions/2` with a sentinel that spares none — so the
open editor carries a warning saying so beside the select, before the
operator chooses; it is a note, not a confirmation, because choosing the
previous company again reverses the change. A reassignment authorizes
`admin.user.update` against the account's **current** company, so its
refusal names that company and never the chosen one. Password reset uses
the same company. Both take the administrator from the sealed scope and
judge their grant in that company through `Authz.can_in_company/5`, so a
grant there allows the write while the administrator is signed in at
another company of the tenant.

**An account with no company is reachable from no screen.** Tenancy is
derived from `company_id`, so `get_tenant_user/2` resolves no user without
one. The detail page mounts no such account, so every fact it shows has a
company to be written through. An account whose
company is archived (soft-deleted) reads as "Archived company" rather than
as no company, and the page shows it read-only: no in-place editor, company
select, role or capability picker, password form, employee action, delete
zone or Impersonate is offered, because every write on the account resolves
its company and an archived one is refused, and the host cannot open a
session for it. One `<.alert kind={:warning}>` under the header says so and
says what it prevents; archiving is final, so it states that as a rule and
names neither the company (no declared Company API returns an archived
company) nor a next step (there is no restore or move, and `users.email` is
unique platform-wide, so a replacement account cannot reuse the email). Hiding the controls is
presentation: each write handler asks Authz and then Core Company again, so
a forged or stale commit is still refused on its fact or through the error
flash. The header is Belimbing's quiet labelled row — History, Impersonate and
"← Back" — with no button; the Impersonate guards (`admin.user.impersonate`,
never the signed-in account, never while impersonating, and now never an
archived-company account, as on the users list) are otherwise unchanged. `Bilimbi.Core.User.Web.ShowLive`'s moduledoc
owns the per-fact rules and DESIGN.md's "Read-first detail pages" owns the
pattern. There is no `/users/:id/edit` route; `FormLive` serves only
`/users/new`.

**`users.prefs` remains intentionally absent.** Belimbing dropped it in
`0200_01_20_000007`. Core User contributes and validates `ui.theme`,
`ui.landing_menu_id`, `ui.dashboard.layout`, `ui.dashboard.sections`, and
`ai.last_used_model_hints`; Base Settings persists their overrides under
`scope_type: 'user'`.

## Deferred

Phoenix routes, forms, mail delivery, login throttling, and the authenticated
Session adapter remain a Web slice. `User::getLastUsedModel()` is Core AI's,
in S4.
