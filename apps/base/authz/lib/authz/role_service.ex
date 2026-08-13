defmodule Bilimbi.Base.Authz.RoleService do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.PrincipalRoleSummary
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.RoleCapability
  alias Bilimbi.Base.Authz.RoleDetails
  alias Bilimbi.Base.Authz.RoleSummary
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope

  @spec list_roles(Scope.t(), map()) :: [RoleSummary.t()]
  def list_roles(%Scope{} = scope, registry) do
    company_ids = directory!(registry).company_ids(scope)

    from(role in Role,
      where:
        (role.is_system and is_nil(role.company_id)) or
          (not role.is_system and role.company_id in ^company_ids),
      order_by: [asc: role.is_system, asc: role.code, asc: role.id]
    )
    |> Repo.all()
    |> Enum.map(&RoleSummary.from_schema/1)
  end

  @spec get_role(Scope.t(), pos_integer(), map()) :: {:ok, RoleDetails.t()} | {:error, :not_found}
  def get_role(%Scope{} = scope, role_id, registry) when is_integer(role_id) and role_id > 0 do
    case eligible_role(scope, role_id, registry) do
      nil ->
        {:error, :not_found}

      %Role{} = role ->
        capabilities =
          from(grant in RoleCapability,
            where: grant.role_id == ^role.id,
            order_by: [asc: grant.capability_key, asc: grant.id],
            select: grant.capability_key
          )
          |> Repo.all()

        principal_roles =
          from(assignment in PrincipalRole,
            where: assignment.role_id == ^role.id,
            where: assignment.company_id in ^directory!(registry).company_ids(scope),
            order_by: [
              asc: assignment.principal_type,
              asc: assignment.principal_id,
              asc: assignment.id
            ]
          )
          |> Repo.all()
          |> Enum.map(&PrincipalRoleSummary.from_schema/1)

        {:ok,
         %RoleDetails{
           role: RoleSummary.from_schema(role, length(capabilities), length(principal_roles)),
           capabilities: capabilities,
           principal_roles: principal_roles
         }}
    end
  end

  @spec create_role(Scope.t(), pos_integer(), map(), map()) ::
          {:ok, RoleSummary.t()} | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_role(%Scope{} = scope, company_id, attributes, registry) when is_map(attributes) do
    if directory!(registry).company_in_scope?(scope, company_id) do
      company_id
      |> Role.custom_changeset(attributes)
      |> Repo.insert()
      |> case do
        {:ok, role} -> {:ok, RoleSummary.from_schema(role)}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :company_not_found}
    end
  end

  @spec update_role(Scope.t(), pos_integer(), map(), map()) ::
          {:ok, RoleSummary.t()}
          | {:error,
             :role_not_found
             | :system_role
             | :company_not_found
             | :role_has_principals
             | :invalid_company_id
             | Ecto.Changeset.t()}
  def update_role(%Scope{} = scope, role_id, attributes, registry) when is_map(attributes) do
    case eligible_role(scope, role_id, registry) do
      nil ->
        {:error, :role_not_found}

      %Role{is_system: true} ->
        {:error, :system_role}

      %Role{} = role ->
        with {:ok, company_id} <- requested_company_id(attributes, role.company_id),
             :ok <- validate_target_company(scope, company_id, registry),
             :ok <- validate_scope_change(role, company_id) do
          role
          |> Role.update_custom_changeset(company_id, attributes)
          |> Repo.update()
          |> case do
            {:ok, updated_role} -> {:ok, RoleSummary.from_schema(updated_role)}
            {:error, changeset} -> {:error, changeset}
          end
        end
    end
  end

  @spec delete_role(Scope.t(), pos_integer(), map()) ::
          {:ok, :deleted} | {:error, :role_not_found | :system_role | Ecto.Changeset.t()}
  def delete_role(%Scope{} = scope, role_id, registry) do
    case eligible_role(scope, role_id, registry) do
      nil ->
        {:error, :role_not_found}

      %Role{is_system: true} ->
        {:error, :system_role}

      %Role{} = role ->
        case Repo.delete(role) do
          {:ok, _role} -> {:ok, :deleted}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec replace_role_capabilities(Scope.t(), pos_integer(), [String.t()], map()) ::
          {:ok, non_neg_integer()}
          | {:error, :role_not_found | :system_role | {:unknown_capabilities, [String.t()]}}
  def replace_role_capabilities(%Scope{} = scope, role_id, capabilities, registry)
      when is_list(capabilities) do
    with {:ok, capabilities} <- validate_capabilities(capabilities, registry) do
      case eligible_role(scope, role_id, registry) do
        nil ->
          {:error, :role_not_found}

        %Role{is_system: true} ->
          {:error, :system_role}

        %Role{} ->
          Repo.transaction(fn ->
            from(grant in RoleCapability, where: grant.role_id == ^role_id)
            |> Repo.delete_all()

            now = now()

            rows =
              Enum.map(capabilities, fn capability ->
                %{
                  role_id: role_id,
                  capability_key: capability,
                  created_at: now,
                  updated_at: now
                }
              end)

            if rows != [], do: Repo.insert_all(RoleCapability, rows)
            length(rows)
          end)
      end
    end
  end

  @spec assign_role(
          Scope.t(),
          pos_integer(),
          :user | :agent,
          pos_integer(),
          pos_integer(),
          map()
        ) :: {:ok, :assigned | :existing} | {:error, :company_not_found | :role_not_found}
  def assign_role(%Scope{} = scope, company_id, principal_type, principal_id, role_id, registry) do
    validate_principal!(principal_type, principal_id)
    directory = directory!(registry)

    cond do
      not directory.company_in_scope?(scope, company_id) ->
        {:error, :company_not_found}

      is_nil(eligible_role(scope, role_id, registry)) ->
        {:error, :role_not_found}

      true ->
        now = now()

        {count, _rows} =
          Repo.insert_all(
            PrincipalRole,
            [
              %{
                company_id: company_id,
                principal_type: Atom.to_string(principal_type),
                principal_id: principal_id,
                role_id: role_id,
                created_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing,
            conflict_target: [:company_id, :principal_type, :principal_id, :role_id]
          )

        {:ok, if(count == 1, do: :assigned, else: :existing)}
    end
  end

  @spec unassign_role(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, :unassigned | :not_found} | {:error, :role_not_found}
  def unassign_role(%Scope{} = scope, role_id, assignment_id, registry)
      when is_integer(role_id) and role_id > 0 and is_integer(assignment_id) and
             assignment_id > 0 do
    if eligible_role(scope, role_id, registry) do
      company_ids = directory!(registry).company_ids(scope)

      {count, _rows} =
        Repo.delete_all(
          from(assignment in PrincipalRole,
            where: assignment.id == ^assignment_id,
            where: assignment.role_id == ^role_id,
            where: assignment.company_id in ^company_ids
          )
        )

      {:ok, if(count == 1, do: :unassigned, else: :not_found)}
    else
      {:error, :role_not_found}
    end
  end

  @spec put_principal_capability(
          Scope.t(),
          pos_integer(),
          :user | :agent,
          pos_integer(),
          String.t(),
          boolean(),
          map()
        ) ::
          {:ok, :stored}
          | {:error, :company_not_found | {:unknown_capabilities, [String.t()]}}
  def put_principal_capability(
        %Scope{} = scope,
        company_id,
        principal_type,
        principal_id,
        capability,
        allowed?,
        registry
      )
      when is_binary(capability) and is_boolean(allowed?) do
    validate_principal!(principal_type, principal_id)

    with {:ok, [capability]} <- validate_capabilities([capability], registry) do
      if directory!(registry).company_in_scope?(scope, company_id) do
        now = now()

        Repo.insert_all(
          PrincipalCapability,
          [
            %{
              company_id: company_id,
              principal_type: Atom.to_string(principal_type),
              principal_id: principal_id,
              capability_key: capability,
              is_allowed: allowed?,
              created_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:is_allowed, :updated_at]},
          conflict_target: [:company_id, :principal_type, :principal_id, :capability_key]
        )

        {:ok, :stored}
      else
        {:error, :company_not_found}
      end
    end
  end

  @spec remove_principal_capability(
          Scope.t(),
          pos_integer(),
          :user | :agent,
          pos_integer(),
          String.t(),
          map()
        ) :: {:ok, :removed | :not_found} | {:error, :company_not_found}
  def remove_principal_capability(
        %Scope{} = scope,
        company_id,
        principal_type,
        principal_id,
        capability,
        registry
      )
      when is_binary(capability) do
    validate_principal!(principal_type, principal_id)

    if directory!(registry).company_in_scope?(scope, company_id) do
      capability = normalize_capability!(capability)
      principal_type = Atom.to_string(principal_type)

      {count, _rows} =
        Repo.delete_all(
          from(grant in PrincipalCapability,
            where: grant.company_id == ^company_id,
            where: grant.principal_type == ^principal_type,
            where: grant.principal_id == ^principal_id,
            where: grant.capability_key == ^capability
          )
        )

      {:ok, if(count == 1, do: :removed, else: :not_found)}
    else
      {:error, :company_not_found}
    end
  end

  defp eligible_role(scope, role_id, registry) do
    company_ids = directory!(registry).company_ids(scope)

    Repo.one(
      from(role in Role,
        where: role.id == ^role_id,
        where:
          (role.is_system and is_nil(role.company_id)) or
            (not role.is_system and role.company_id in ^company_ids)
      )
    )
  end

  defp validate_capabilities(capabilities, registry) do
    capabilities = capabilities |> Enum.map(&String.downcase/1) |> Enum.uniq() |> Enum.sort()
    unknown = capabilities -- registry.capabilities

    if unknown == [], do: {:ok, capabilities}, else: {:error, {:unknown_capabilities, unknown}}
  end

  defp requested_company_id(attributes, current_company_id) do
    case Map.fetch(attributes, :company_id) do
      {:ok, value} ->
        normalize_company_id(value)

      :error ->
        case Map.fetch(attributes, "company_id") do
          {:ok, value} -> normalize_company_id(value)
          :error -> {:ok, current_company_id}
        end
    end
  end

  defp normalize_company_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_company_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {company_id, ""} when company_id > 0 -> {:ok, company_id}
      _other -> {:error, :invalid_company_id}
    end
  end

  defp normalize_company_id(_value), do: {:error, :invalid_company_id}

  defp validate_target_company(scope, company_id, registry) do
    if directory!(registry).company_in_scope?(scope, company_id),
      do: :ok,
      else: {:error, :company_not_found}
  end

  defp validate_scope_change(%Role{company_id: company_id}, company_id), do: :ok

  defp validate_scope_change(%Role{id: role_id}, _company_id) do
    if Repo.exists?(from(assignment in PrincipalRole, where: assignment.role_id == ^role_id)),
      do: {:error, :role_has_principals},
      else: :ok
  end

  defp normalize_capability!(capability) do
    case capability |> String.trim() |> String.downcase() do
      "" -> raise ArgumentError, "capability must not be blank"
      normalized -> normalized
    end
  end

  defp directory!(%{company_directory: nil}) do
    raise ArgumentError, "no installed module contributes the Authz company directory"
  end

  defp directory!(%{company_directory: directory}), do: directory

  defp validate_principal!(type, id) when type in [:user, :agent] and is_integer(id) and id > 0,
    do: :ok

  defp validate_principal!(_type, _id) do
    raise ArgumentError, "principal must be a :user or :agent with a positive ID"
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
