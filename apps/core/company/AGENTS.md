# Core Company

## Live company ids

Authorization and other "is this company still live" checks use
`list_live_company_ids/1`, `live_company?/2`, or
`live_company_ids_query/1`. `list_tenant_company_ids/1` includes soft-deleted
companies for the user list; using it for authorization would treat an
archived company as in scope. The docs table in
[`docs/README.md`](docs/README.md#tenant-wide-reads) is the contract.

## Selectable company reach

`list_selectable_companies/2` and `authorize_company_target/3` take the sealed scope. The clause derives the actor with `Bilimbi.Base.Authz.scope_actor/1` (`apps/base/authz/lib/authz.ex`); the docs on those functions in `apps/core/company/lib/company.ex` own the contract. Pass the scope. The actor clauses stay for an `Actor` the caller already holds. Do not build one with `Authz.actor/5` to call them.

Legal entity type, department type, and relationship writes take that same scope and check `admin.company.create`, `admin.company.update`, or `admin.company.delete` at call time (`authorize/2` in `reference_types.ex` and `relationships.ex`). A `can_*?` assign only hides the control. Pass the scope; do not add a write that trusts the mount-time assign.

Reference types, departments, relationships, and external accesses are implemented in those sibling modules. `company.ex` keeps the public names with `defdelegate`. Add the next aggregate there, not as more queries in `company.ex`.

## Maintaining this file

Keep this note short. Point at the function docs; do not copy them.
