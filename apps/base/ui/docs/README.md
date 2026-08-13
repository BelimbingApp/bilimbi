# Base UI

**Stable module ID:** `base/ui` · **Layer:** Base · required

Owns the shared presentation contracts every UI-bearing module needs:
layouts, core components, the `use Bilimbi.Base.UI, :live_view` facade, and
`RouteContract` for compile-time `~p` verification.

This package is dependency-light. It depends on Phoenix libraries and
`base/module_registry` only — never on Tenancy, Authz, Session, or `:web`.
Authentication `on_mount` hooks stay in `BilimbiWeb.UserAuth`.
