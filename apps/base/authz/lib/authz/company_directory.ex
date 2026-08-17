defmodule Bilimbi.Base.Authz.CompanyDirectory do
  @moduledoc """
  Lower-layer contract used to validate live company ownership without Base naming Core.

  `company_ids/1` and `company_in_scope?/2` answer questions about **ids**, which
  is all a validation needs. A screen needs more: Belimbing's role create form
  (`app/Base/Authz/Livewire/Roles/Create.php`) renders a company `<select>` and
  satisfies `base_authz_roles_custom_company_check` by construction rather than
  by validation. It gets its options from `Company::query()->forTenant(...)`,
  which is Base querying Core directly — exactly what this seam exists to
  prevent. `companies_in_scope/1` is the naming half of the same seam (#183).
  """

  alias Bilimbi.Base.Tenancy.Scope

  @typedoc """
  A company the scope may reference, named as the user should see it.

  Deliberately a bare map rather than a struct: the struct would have to live in
  Base and be built by Core, which is the coupling this contract avoids.
  """
  @type named_company :: %{id: pos_integer(), name: String.t()}

  @callback company_ids(Scope.t()) :: [pos_integer()]
  @callback company_in_scope?(Scope.t(), pos_integer()) :: boolean()

  @doc """
  The same companies `company_ids/1` reports, carrying display names.

  Two properties callers depend on, both asserted in
  `apps/base/authz/test/company_directory_contract_test.exs`:

  - **The id set matches `company_ids/1` exactly.** A picker that offered a
    company `company_in_scope?/2` then rejected would be a form that fails on
    submit for a value it supplied itself.
  - **Ordered by the name being displayed, case-insensitively.** Belimbing
    orders its options by `name` and gets case-insensitivity from the database
    collation. Sorting raw binaries in Elixir is codepoint order, which files
    every lowercase initial after every uppercase one — "eMart" below "Zulu" —
    and sorting by anything the user cannot see reads as unsorted.
  """
  @callback companies_in_scope(Scope.t()) :: [named_company()]
end
