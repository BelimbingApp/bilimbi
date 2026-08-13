defmodule Bilimbi.Base.Authz.Diagnostics do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.RoleCapability
  alias Bilimbi.Base.Repo

  @spec unknown_persisted_capabilities([String.t()]) :: %{
          role_grants: [map()],
          principal_grants: [map()]
        }
  def unknown_persisted_capabilities(known_capabilities) do
    known = MapSet.new(known_capabilities)

    role_grants =
      from(grant in RoleCapability,
        select: %{role_id: grant.role_id, capability: grant.capability_key},
        order_by: [grant.capability_key, grant.role_id]
      )
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(known, &1.capability))

    principal_grants =
      from(grant in PrincipalCapability,
        select: %{
          company_id: grant.company_id,
          principal_type: grant.principal_type,
          principal_id: grant.principal_id,
          capability: grant.capability_key,
          allowed: grant.is_allowed
        },
        order_by: [grant.capability_key, grant.principal_type, grant.principal_id]
      )
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(known, &1.capability))

    %{role_grants: role_grants, principal_grants: principal_grants}
  end
end
