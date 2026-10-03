# Core Company

## Selectable company reach

`list_selectable_companies/2` and `authorize_company_target/3` take the sealed scope. The clause derives the actor with `Bilimbi.Base.Authz.scope_actor/1` (`apps/base/authz/lib/authz.ex`); the docs on those functions in `apps/core/company/lib/company.ex` own the contract. Pass the scope. The actor clauses stay for an `Actor` the caller already holds. Do not build one with `Authz.actor/5` to call them.

Legal entity type, department type, and relationship writes take that same scope and check `admin.company.create`, `admin.company.update`, or `admin.company.delete` at call time (`authorize/2` in `company.ex`). A `can_*?` assign only hides the control. Pass the scope; do not add a write that trusts the mount-time assign.

## Maintaining this file

Keep this note short. Point at the function docs; do not copy them.
