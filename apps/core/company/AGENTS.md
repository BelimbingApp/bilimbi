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

Reference types, departments, relationships, and external accesses live in `reference_types.ex`, `departments.ex`, `relationships.ex`, and `external_accesses.ex`. `company.ex` keeps the public names with `defdelegate`; the `@doc` on those functions there owns the contract. Add the next aggregate beside those modules, not as more queries in `company.ex`.

## Status is a lifecycle

A company's status changes only through `archive_company/3`,
`suspend_company/3`, `activate_company/3` or `reactivate_company/3`, which
check the capability, judge the transition and record a retained
`company.<event>` audit action in one transaction. `update_company/3`
refuses a `status` key. `archive_company/3` and `suspend_company/3` also
refuse the tenant's primary company (`:primary_company`) and the performing
account's own signed-in company (`:own_company`); a page reports each by
name, never as a generic failure. Every operation is authorized against
the company it acts on through `authorize_company_target/3`: another
company needs `admin.company.tenant-wide.manage` as well, and the page's
`can_lifecycle?` follows the same rule. The table is [`docs/README.md`](docs/README.md#lifecycle)
and the bodies are `lifecycle.ex`. A page offers `lifecycle_operations/1`'s
answer and nothing else; do not add a status select or a second transition
list.

## Archived is read-only

A write to a company or into it begins with `require_writable_company/2`
(`lock_writable_company/2` under the company row lock); a Base module asks
`Bilimbi.Base.Authz.company_writable/2`. Both answer
`{:error, :company_archived}` from `WritableCompany`. Do not compare
`status == "archived"` in a sibling or a page, and do not guard a read with
it. The write inventory is [`docs/README.md`](docs/README.md#an-archived-company-is-read-only).

## Maintaining this file

Keep this note short. Point at the function docs; do not copy them.
