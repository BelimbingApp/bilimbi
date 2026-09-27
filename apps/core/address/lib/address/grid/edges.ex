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

  alias Bilimbi.Core.Address.Addressable
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee

  @doc false
  def company_addresses(_scope), do: attachments(Company.addressable_identity())

  @doc false
  def employee_addresses(_scope), do: attachments(Employee.addressable_identity())

  @doc false
  def company_primary_address(_scope) do
    from(x in Addressable,
      where: x.addressable_type == ^Company.addressable_identity(),
      distinct: [asc: x.addressable_id],
      order_by: [asc: x.addressable_id, desc: x.is_primary, asc: x.priority, asc: x.id],
      select: %{from_key: x.addressable_id, to_key: x.address_id}
    )
  end

  defp attachments(identity) do
    from(x in Addressable,
      where: x.addressable_type == ^identity,
      select: %{from_key: x.addressable_id, to_key: x.address_id}
    )
  end
end
