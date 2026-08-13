defmodule Bilimbi.Base.Audit do
  @moduledoc """
  Public API for durable mutation and action facts.

  Recording accepts caller-assigned identity (`tenant_id`, `company_id`, and
  the actor pair) because rows outlive their subjects and `tenant_id` is
  nullable. Listing is tenant-scoped: a `Bilimbi.Base.Tenancy.Scope` is
  required, and null-tenant rows are invisible to every tenant.
  """

  import Ecto.Query

  alias Bilimbi.Base.Audit.Action
  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Mutation
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope

  @spec record_mutation(map()) :: {:ok, Mutation.t()} | {:error, Ecto.Changeset.t()}
  def record_mutation(attributes) when is_map(attributes) do
    attributes
    |> MutationSchema.changeset()
    |> Repo.insert()
    |> map_mutation()
  end

  @spec record_action(map()) :: {:ok, Action.t()} | {:error, Ecto.Changeset.t()}
  def record_action(attributes) when is_map(attributes) do
    attributes
    |> ActionSchema.changeset()
    |> Repo.insert()
    |> map_action()
  end

  @spec list_mutations(Scope.t()) :: {:ok, [Mutation.t()]}
  def list_mutations(%Scope{} = scope) do
    mutations =
      from(mutation in Tenancy.scope_query(MutationSchema, scope),
        order_by: [asc: mutation.occurred_at, asc: mutation.id]
      )
      |> Repo.all()
      |> Enum.map(&Mutation.from_schema/1)

    {:ok, mutations}
  end

  @spec list_actions(Scope.t()) :: {:ok, [Action.t()]}
  def list_actions(%Scope{} = scope) do
    actions =
      from(action in Tenancy.scope_query(ActionSchema, scope),
        order_by: [asc: action.occurred_at, asc: action.id]
      )
      |> Repo.all()
      |> Enum.map(&Action.from_schema/1)

    {:ok, actions}
  end

  defp map_mutation({:ok, mutation}), do: {:ok, Mutation.from_schema(mutation)}
  defp map_mutation({:error, changeset}), do: {:error, changeset}

  defp map_action({:ok, action}), do: {:ok, Action.from_schema(action)}
  defp map_action({:error, changeset}), do: {:error, changeset}
end
