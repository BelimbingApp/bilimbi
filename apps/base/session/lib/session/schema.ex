defmodule Bilimbi.Base.Session.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "sessions" do
    field(:user_id, :id)
    field(:ip_address, :string)
    field(:user_agent, :string)
    field(:payload, :string)
    field(:last_activity, :integer)
  end

  @type t :: %__MODULE__{}

  @spec changeset(String.t(), String.t(), map() | keyword()) :: Ecto.Changeset.t()
  def changeset(id, payload, attributes) when is_binary(id) and is_binary(payload) do
    %__MODULE__{}
    |> cast(Map.new(attributes), [:user_id, :ip_address, :user_agent, :last_activity])
    |> put_change(:id, id)
    |> put_change(:payload, payload)
    |> validate_required([:id, :payload, :last_activity])
    |> validate_length(:id, max: 255)
    |> validate_length(:ip_address, max: 45)
    |> validate_number(:user_id, greater_than: 0)
    |> validate_number(:last_activity, greater_than_or_equal_to: 0)
  end
end
