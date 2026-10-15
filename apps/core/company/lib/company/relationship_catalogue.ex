defmodule Bilimbi.Core.Company.RelationshipCatalogue do
  @moduledoc """
  The existing platform-wide relationship role catalogue. Reads are shared;
  writes require the platform operator and the same company capability as the
  reference-type page. Stable codes and IDs survive renaming and retirement.
  A role means: the related company (or, in Core Person, the related person)
  is `name` to the source company; `inverse_name`
  describes the source from the related company's perspective. No role grants
  portal access. Access remains an independent, explicit workflow.
  """
  import Ecto.Query
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.RelationshipType
  alias Ecto.Changeset

  @defaults [
    %{
      code: "vendor",
      name: "Vendor / Supplier",
      description: "The related company supplies the source company.",
      metadata: %{"inverse_name" => "Customer"}
    },
    %{
      code: "customer",
      name: "Customer",
      description: "The related company buys from the source company.",
      metadata: %{"inverse_name" => "Vendor / Supplier"}
    },
    %{
      code: "prospect",
      name: "Prospect",
      description:
        "The related organisation or person may become a customer of the source company.",
      metadata: %{"inverse_name" => "Prospective vendor / Supplier"}
    },
    %{
      code: "partner",
      name: "Partner",
      description: "The companies collaborate as partners.",
      metadata: %{"inverse_name" => "Partner"}
    }
  ]

  def ensure_defaults(repo) do
    # Reference seed only. Never overwrite an operator's rename or retirement.
    Enum.each(@defaults, fn attrs ->
      unless repo.exists?(from(t in RelationshipType, where: t.code == ^attrs.code)) do
        repo.insert!(RelationshipType.changeset(%RelationshipType{}, attrs))
      end
    end)

    :ok
  end

  def list do
    types = Repo.all(from t in RelationshipType, order_by: [asc: t.name, asc: t.id])
    {:ok, Enum.map(types, &%{&1 | inverse_name: RelationshipType.inverse_name(&1)})}
  end

  def get(id) do
    case Repo.get(RelationshipType, id) do
      nil -> {:error, :not_found}
      type -> {:ok, %{type | inverse_name: RelationshipType.inverse_name(type)}}
    end
  end

  def create(%Scope{} = scope, attrs) do
    with {:ok, cs} <- changeset(scope, nil, attrs, "admin.company.create"),
         do: Bilimbi.Base.Audit.with_scope(scope, fn -> Repo.insert(cs) end)
  end

  def update(%Scope{} = scope, id, attrs) do
    with {:ok, cs} <- changeset(scope, id, attrs, "admin.company.update"),
         do: Bilimbi.Base.Audit.with_scope(scope, fn -> Repo.update(cs) end)
  end

  def toggle(%Scope{} = scope, id) do
    with {:ok, type} <- get(id),
         do: __MODULE__.update(scope, id, %{is_active: not type.is_active})
  end

  def preview(%Scope{} = scope, id, attrs) do
    capability = if is_nil(id), do: "admin.company.create", else: "admin.company.update"

    with {:ok, cs} <- changeset(scope, id, attrs, capability),
         {:ok, _} <-
           cs
           |> Changeset.unsafe_validate_unique(:code, Repo)
           |> Changeset.apply_action(:validate) do
      {:ok,
       %{
         summary: "Change company relationship role",
         changes:
           Enum.map(cs.changes, fn {field, value} ->
             %{field: to_string(field), from: Map.get(cs.data, field), to: value}
           end)
       }}
    end
  end

  defp changeset(scope, id, attrs, capability) do
    with true <- Scope.platform_operator?(scope),
         %{allowed: true} <- Authz.can(scope, capability),
         {:ok, type} <- if(is_nil(id), do: {:ok, %RelationshipType{}}, else: get(id)) do
      cs =
        if is_nil(id),
          do: RelationshipType.changeset(type, attrs),
          else: RelationshipType.update_changeset(type, attrs)

      {:ok, cs}
    else
      false -> {:error, :forbidden}
      %{allowed: false} -> {:error, :forbidden}
      error -> error
    end
  end
end
