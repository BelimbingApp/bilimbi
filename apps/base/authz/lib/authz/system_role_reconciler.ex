defmodule Bilimbi.Base.Authz.SystemRoleReconciler do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleCapability
  alias Ecto.Adapters.SQL

  @spec reconcile(Ecto.Repo.t(), map()) ::
          {:ok, %{roles: non_neg_integer(), capabilities: non_neg_integer()}} | {:error, term()}
  def reconcile(repo, registry) do
    repo.transaction(fn ->
      SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock(hashtext('bilimbi-authz-system-role-reconcile'))",
        []
      )

      capability_count =
        registry.roles
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.reduce(0, fn {_code, definition}, count ->
          role = upsert_role!(repo, definition)
          count + sync_capabilities!(repo, role, definition)
        end)

      %{roles: map_size(registry.roles), capabilities: capability_count}
    end)
  end

  defp upsert_role!(repo, definition) do
    roles =
      from(role in Role,
        where: is_nil(role.company_id) and role.code == ^definition.code,
        order_by: role.id,
        limit: 2
      )
      |> repo.all()

    attributes = %{
      name: definition.name,
      description: definition.description,
      is_system: true,
      grant_all: definition.grant_all
    }

    case roles do
      [] ->
        %Role{company_id: nil, code: definition.code}
        |> Ecto.Changeset.change(attributes)
        |> repo.insert!()

      [role] ->
        role |> Ecto.Changeset.change(attributes) |> repo.update!()

      duplicates ->
        repo.rollback({:duplicate_system_role, definition.code, Enum.map(duplicates, & &1.id)})
    end
  end

  defp sync_capabilities!(repo, role, %{grant_all: true}) do
    {deleted_count, _rows} =
      from(grant in RoleCapability, where: grant.role_id == ^role.id)
      |> repo.delete_all()

    deleted_count
  end

  defp sync_capabilities!(repo, role, definition) do
    desired = definition.capabilities

    delete_query = from(grant in RoleCapability, where: grant.role_id == ^role.id)

    {deleted_count, _rows} =
      if desired == [] do
        repo.delete_all(delete_query)
      else
        delete_query |> where([grant], grant.capability_key not in ^desired) |> repo.delete_all()
      end

    existing =
      from(grant in RoleCapability,
        where: grant.role_id == ^role.id and grant.capability_key in ^desired,
        select: grant.capability_key
      )
      |> repo.all()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      desired
      |> Kernel.--(existing)
      |> Enum.map(fn capability ->
        %{
          role_id: role.id,
          capability_key: capability,
          created_at: now,
          updated_at: now
        }
      end)

    inserted_count = if rows == [], do: 0, else: elem(repo.insert_all(RoleCapability, rows), 0)
    deleted_count + inserted_count
  end
end
