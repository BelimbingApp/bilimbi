# Base UI

**Stable module ID:** `base/ui` · **Layer:** Base · required

Owns the shared presentation contracts every UI-bearing module needs:
layouts, core components, the `use Bilimbi.Base.UI, :live_view` facade, and
`RouteContract` for compile-time `~p` verification.

The LiveView and LiveComponent facades wrap `handle_event/3` so an unexpected
action exception is logged and shown as an honest error flash without replacing
the mounted screen. Exceptions that carry deliberate framework outcomes, such
as authorization denial, invalid changesets, and missing records, still
propagate. Rendering and other lifecycle callbacks are not recovered.

This package is dependency-light. It depends on Phoenix libraries and
`base/module_registry` only — never on Tenancy, Authz, Session, or `:web`.
Authentication `on_mount` hooks stay in `BilimbiWeb.UserAuth`.
