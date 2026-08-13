defmodule Bilimbi.Base.Audit.ActionSchema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @actor_types ~w(user agent console scheduler queue)
  @assigned [:tenant_id, :company_id, :actor_type, :actor_id]
  @cast_fields [
    :actor_role,
    :ip_address,
    :url,
    :user_agent,
    :event,
    :payload,
    :trace_id,
    :is_retained,
    :occurred_at
  ]
  @required [:actor_type, :actor_id, :event, :occurred_at]

  @primary_key {:id, :id, autogenerate: true}

  schema "base_audit_actions" do
    field :company_id, :id
    field :tenant_id, :id
    field :actor_type, :string
    field :actor_id, :id
    field :actor_role, :string
    field :ip_address, Bilimbi.Base.Audit.Inet
    field :url, :string
    field :user_agent, :string
    field :event, :string
    field :payload, Bilimbi.Base.Database.Json
    field :trace_id, :string
    field :is_retained, :boolean, default: false
    field :occurred_at, :naive_datetime
  end

  @type t :: %__MODULE__{}

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attributes) when is_map(attributes) do
    %__MODULE__{}
    |> cast(attributes, @cast_fields)
    |> put_assigned(attributes)
    |> update_change(:occurred_at, &truncate_occurred_at/1)
    |> validate_required(@required)
    |> validate_inclusion(:actor_type, @actor_types)
    |> validate_length(:actor_type, max: 40)
    |> validate_length(:actor_role, max: 100)
    |> validate_length(:user_agent, max: 80)
    |> validate_length(:event, max: 255)
    |> validate_length(:trace_id, max: 12)
  end

  # Identity columns arrive from the recording caller, never from a form cast.
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
