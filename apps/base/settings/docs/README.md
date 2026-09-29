# Base Settings

Base Settings owns the canonical `base_settings` table, module-contributed
runtime definitions, explicit runtime-state claims, scope resolution, and
compatible encryption for adopted Belimbing rows.

Definitions are immutable source facts loaded through ADR 0004's
descriptor-owned contribution provider. Each definition owns its value type,
allowed scopes, default, encryption policy, and module provenance. A missing
row resolves to that declared default; an undeclared and unclaimed key raises.

An editable definition may declare a capability in addition to its UI group.
The generic settings screen filters its server-owned field plan by the live
scope's capabilities; a hidden key is therefore excluded from forged/direct
submissions as well as from rendering. The route's group capability controls
access to the screen, while the definition capability controls each field.

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
