defmodule Bilimbi.Core.User.Grid.UsersSource do
  @moduledoc """
  The users of the scope's tenant, for the grid catalog.

  `users` carries no tenant column; a user belongs to the tenant through
  the company it is affiliated with, so the rows are those whose company
  the tenant owns, exactly as `Bilimbi.Core.User.list_users/1` reads them.
  A user with no company belongs to no tenant-scoped list and is not here.
  Only declared fields are selected: the credential columns never enter a
  grid statement.
  """

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User.Schema

  @impl true
  def query(scope) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    from(u in Schema,
      where: u.company_id in ^company_ids,
      select: %{
        id: u.id,
        company_id: u.company_id,
        employee_id: u.employee_id,
        name: u.name,
        email: u.email,
        email_verified_at: u.email_verified_at,
        created_at: u.created_at,
        updated_at: u.updated_at
      }
    )
  end
end
