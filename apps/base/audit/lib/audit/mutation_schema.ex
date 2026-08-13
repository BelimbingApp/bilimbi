defmodule Bilimbi.Base.Audit.MutationSchema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @actor_types ~w(user agent guest console scheduler queue)
  @assigned [:company_id, :actor_type, :actor_id]
  @cast_fields [
    :actor_role,
    :ip_address,
    :url,
    :user_agent,
    :auditable_type,
    :auditable_id,
    :subject_name,
    :subject_id,
    :subject_identifier,
    :source,
    :event,
    :old_values,
    :new_values,
    :trace_id,
    :occurred_at
  ]
  @required [
    :actor_type,
    :actor_id,
    :auditable_type,
    :auditable_id,
    :source,
    :event,
    :occurred_at
  ]

  @primary_key {:id, :id, autogenerate: true}

  schema "base_audit_mutations" do
    field :company_id, :id
    field :tenant_id, :id
    field :actor_type, :string
    field :actor_id, :id
    field :actor_role, :string
    field :ip_address, Bilimbi.Base.Audit.Inet
    field :url, :string
    field :user_agent, :string
    field :auditable_type, :string
    field :auditable_id, :string
    field :subject_name, :string
    field :subject_id, :string
    field :subject_identifier, :string
    field :source, :string, default: "listener"
    field :event, :string
    field :old_values, Bilimbi.Base.Database.Json
    field :new_values, Bilimbi.Base.Database.Json
    field :trace_id, :string
    field :occurred_at, :naive_datetime
  end

  @type t :: %__MODULE__{}

  @spec changeset(map(), pos_integer() | nil) :: Ecto.Changeset.t()
  def changeset(attributes, tenant_id)
      when is_map(attributes) and (is_nil(tenant_id) or (is_integer(tenant_id) and tenant_id > 0)) do
    %__MODULE__{}
    |> cast(attributes, @cast_fields)
    |> put_assigned(attributes)
    |> put_change(:tenant_id, tenant_id)
    |> update_change(:occurred_at, &truncate_occurred_at/1)
    |> validate_required(@required)
    |> validate_inclusion(:actor_type, @actor_types)
    |> validate_length(:actor_type, max: 40)
    |> validate_length(:actor_role, max: 100)
    |> validate_length(:user_agent, max: 80)
    |> validate_length(:auditable_type, max: 255)
    |> validate_length(:auditable_id, max: 128)
    |> validate_length(:subject_name, max: 255)
    |> validate_length(:subject_id, max: 128)
    |> validate_length(:subject_identifier, max: 255)
    |> validate_length(:source, max: 20)
    |> validate_length(:event, max: 20)
    |> validate_length(:trace_id, max: 12)
  end

  # Company and actor identity arrive from the recording caller, never from a form cast.
  # Tenant identity is supplied by the public API from a Scope or :unscoped, never the map.
  defp put_assigned(changeset, attributes) do
    Enum.reduce(@assigned, changeset, fn field, acc ->
      case fetch_attribute(attributes, field) do
        :error -> acc
        {:ok, value} -> put_change(acc, field, value)
      end
    end)
  end

  defp fetch_attribute(attributes, field) do
    with :error <- Map.fetch(attributes, field) do
      Map.fetch(attributes, Atom.to_string(field))
    end
  end

  defp truncate_occurred_at(%NaiveDateTime{} = datetime),
    do: NaiveDateTime.truncate(datetime, :second)

  defp truncate_occurred_at(other), do: other
end
