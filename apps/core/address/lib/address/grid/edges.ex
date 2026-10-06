defmodule Bilimbi.Core.Address.Grid.Edges do
  @moduledoc """
  The attachment edges Core Address owns: which addresses belong to a
  company or an employee, through the polymorphic `addressables` table
  that no key pair expresses. The type discriminator is each owner's
  addressable identity, so a company's edge never reaches an employee's
  address row of the same numeric id.

  `company_primary_address/1` picks one row per company (primary first,
  then by priority), so the `primary_address` link is a `:one` link.
  """

  import Ecto.Query

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address.Addressable
  alias Bilimbi.Core.Address.Schema
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee

  # Every edge is bounded to the tenant's live addresses, the same rows the
  # addresses source returns, so an attachment of another tenant's address
  # is never scanned, let alone reached.
  @doc false
  def company_addresses(scope), do: attachments(scope, Company.addressable_identity())

  @doc false
  def employee_addresses(scope), do: attachments(scope, Employee.addressable_identity())

  @doc false
  def company_primary_address(scope) do
    from([x, _address] in attachments(scope, Company.addressable_identity()),
      distinct: [asc: x.addressable_id],
      order_by: [asc: x.addressable_id, desc: x.is_primary, asc: x.priority, asc: x.id]
    )
  end

  defp attachments(scope, identity) do
    addresses =
      from(a in Tenancy.scope_query(Schema, scope),
        where: is_nil(a.deleted_at),
        select: %{id: a.id}
      )

    from(x in Addressable,
      join: address in subquery(addresses),
      on: address.id == x.address_id,
      where: x.addressable_type == ^identity,
      select: %{from_key: x.addressable_id, to_key: x.address_id}
    )
  end
end
