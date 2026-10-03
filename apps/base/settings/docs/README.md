# Base Settings

Base Settings owns the canonical `base_settings` table, module-contributed
runtime definitions, explicit runtime-state claims, scope resolution, and
compatible encryption for adopted Belimbing rows.

Definitions are immutable source facts loaded through ADR 0004's
descriptor-owned contribution provider. Each definition owns its value type,
allowed scopes, default, encryption policy, and module provenance. A missing
row resolves to that declared default; an undeclared and unclaimed key raises.

A definition may declare `validator: {module, function, message}` when its
owner has a rule beyond the value type, such as `localization.timezone`
requiring a valid IANA timezone. `Settings.put/3` and every settings screen
run it; an invalid value is refused with that message and never stored.

An editable definition may declare a capability in addition to its UI group.
The generic settings screen filters its server-owned field plan by the live
scope's capabilities; a hidden key is therefore excluded from forged/direct
submissions as well as from rendering. The route's group capability controls
access to the screen, while the definition capability controls each field.

The operator page at `/system/settings` starts at Global. Accounts granted
`base.settings.company.manage` can choose a live company they may target;
other companies in the tenant also require `admin.company.tenant-wide.manage`.
The selector uses the host's `Bilimbi.Base.Settings.CompanyScopeService`
implementation, configured as `:company_scope_service`, so Base does not depend
on Core business implementations. Every save, clear, and stored-value reveal
rechecks the company target.

Company scope discovers every editable group with company-scoped definitions.
It shows effective values and distinguishes a company override from inheritance
from global, tenant, or the declared default. Global-only fields are excluded,
including from direct submissions. Clear override confirms and deletes only
that company's value; the shared restore action clears the confirmed fields.
Changing scope drops pending confirmations and reloads storage. Saves and clears
use the existing validated Form API and Repo mutation audit trail.

The database lookup cascade is user → company → tenant → global. A definition
may opt into any subset. `scope_type` and `scope_id` deliberately have no
foreign keys because settings may outlive their current subject and the source
schema treats them as polymorphic identities.

Encrypted definitions use the Laravel AES-256-CBC envelope so adopted values
remain readable when `BELIMBING_APP_KEY` is supplied. The key is optional until
an encrypted row is read or written, never logged, and never stored in this
table.

The group screen never renders a stored encrypted value; it shows a
keep-current mask. A viewer explicitly granted `base.settings.secret.view`
may ask to show one stored value after re-entering their own password. Base
Settings calls the host seam `Bilimbi.Base.Settings.SecretRevealService`
(configured as `:secret_reveal_service`), which the Web host implements in
`BilimbiWeb.SecretReveal` to check the grant and password, throttle failures,
and audit every attempt without the value. The value stays visible for the
definition's `reveal_duration_ms` (default 10 000, bounded 1 000–60 000).

Single-row settings reads cache both hits and misses by key and scope in a
node-local ETS cache, started with the Settings application, with a 30-second
TTL and periodic expiry reclamation. `Settings.put/3` and `Settings.delete/2`
invalidate the matching scope after a successful commit; transaction reads
bypass the cache, and publication cannot undo a concurrent invalidation.
Direct writes and writes on other nodes may remain stale until expiry.
PubSub invalidation is a multi-node follow-up; it is not implemented yet.
Settings forms fetch all rows for their requested keys and scope chain in one
query, then derive values and override metadata from that snapshot.
