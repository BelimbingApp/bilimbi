defmodule Bilimbi.Base.Authz.PrincipalRoleSummary do
  @moduledoc "Stable read model for one principal-to-role assignment."

  alias Bilimbi.Base.Authz.PrincipalRole

  alias Bilimbi.Base.Authz.Role

  @enforce_keys [:id, :company_id, :principal_type, :principal_id, :role_id]
  defstruct [
    :id,
    :company_id,
    :principal_type,
    :principal_id,
    :principal_name,
    :role_id,
    :role_name,
    :role_code,
    :role_is_system,
    :role_grant_all,
    :created_at
  ]

  @type t :: %__MODULE__{}

  @doc false
  @spec from_schema(PrincipalRole.t()) :: t()
  def from_schema(%PrincipalRole{} = assignment) do
    %__MODULE__{
      id: assignment.id,
      company_id: assignment.company_id,
      principal_type: assignment.principal_type,
      principal_id: assignment.principal_id,
      role_id: assignment.role_id,
      created_at: assignment.created_at
    }
  end

  @doc false
  @spec from_schema(PrincipalRole.t(), Role.t()) :: t()
  def from_schema(%PrincipalRole{} = assignment, %Role{} = role) do
    assignment
    |> from_schema()
    |> Map.merge(%{
      role_name: role.name,
      role_code: role.code,
      role_is_system: role.is_system,
      role_grant_all: role.grant_all
    })
  end

  @doc """
  Builds the read model, naming the principal when the directory resolved it.

  `names` is keyed on the `{kind, id}` **pair**: a user and an employee can
  share an id, and keying on the id alone would show one of them the other's
  name. An absent key is not an error -- a principal outside the actor's
  tenant, or one whose module is not installed, keeps its durable id (#441).
  """
  @spec from_schema(PrincipalRole.t(), Role.t(), %{{atom(), pos_integer()} => String.t()}) :: t()
  def from_schema(%PrincipalRole{} = assignment, %Role{} = role, names) when is_map(names) do
    # `from_schema/2` finishes with `Map.merge/2`, which keeps the struct at
    # runtime but loses it for the type checker, so this updates as a map.
    %{from_schema(assignment, role) | principal_name: principal_name(assignment, names)}
  end

  defp principal_name(%{principal_type: type, principal_id: id}, names) do
    Map.get(names, {kind(type), id})
  end

  defp kind("user"), do: :user
  defp kind("agent"), do: :agent
  defp kind(_other), do: nil
end
