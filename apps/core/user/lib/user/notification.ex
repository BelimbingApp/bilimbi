defmodule Bilimbi.Core.User.Notification do
  @moduledoc """
  Ecto schema for polymorphic database notifications (`notifications` table).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :bigint

  defmodule Data do
    @moduledoc """
    Custom Ecto.Type mapping JSON map data to a `text` database column.
    """
    use Ecto.Type

    @impl true
    def type, do: :string

    @impl true
    def cast(map) when is_map(map), do: {:ok, stringify_keys(map)}

    def cast(str) when is_binary(str) do
      case Jason.decode(str) do
        {:ok, map} when is_map(map) -> {:ok, stringify_keys(map)}
        _ -> {:error, [message: "is not valid JSON"]}
      end
    end

    def cast(_), do: :error

    defp stringify_keys(map) when is_map(map) do
      Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
    end

    defp stringify_value(val) when is_map(val), do: stringify_keys(val)
    defp stringify_value(val), do: val

    @impl true
    def load(str) when is_binary(str) do
      case Jason.decode(str) do
        {:ok, map} -> {:ok, map}
        _ -> {:ok, %{}}
      end
    end

    def load(nil), do: {:ok, %{}}

    @impl true
    def dump(map) when is_map(map) do
      case Jason.encode(map) do
        {:ok, str} -> {:ok, str}
        _ -> :error
      end
    end

    def dump(str) when is_binary(str), do: {:ok, str}
    def dump(_), do: :error
  end

  schema "notifications" do
    field(:type, :string, default: "generic")
    field(:notifiable_type, :string, default: "App\\Core\\User\\Models\\User")
    field(:notifiable_id, :integer)
    field(:data, Data)
    field(:read_at, :naive_datetime)

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for inserting or updating a notification."
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:id, :type, :notifiable_type, :notifiable_id, :data, :read_at])
    |> validate_required([:type, :notifiable_type, :notifiable_id, :data])
    |> validate_number(:notifiable_id, greater_than: 0)
  end

  @doc "Returns a changeset setting read_at to the current timestamp."
  def mark_read_changeset(notification) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(notification, read_at: now)
  end

  @doc "Returns true if the notification has been read."
  def read?(%__MODULE__{read_at: read_at}), do: not is_nil(read_at)

  @doc "Returns true if the notification is unread."
  def unread?(%__MODULE__{read_at: read_at}), do: is_nil(read_at)

  @doc "Extracts title from data payload or derives from type."
  def title(%__MODULE__{data: data, type: type}) when is_map(data) do
    Map.get(data, "title") || Map.get(data, :title) || format_type_title(type)
  end

  def title(_), do: "Notification"

  @doc "Extracts body from data payload."
  def body(%__MODULE__{data: data}) when is_map(data) do
    Map.get(data, "body") || Map.get(data, :body) || ""
  end

  def body(_), do: ""

  @doc "Extracts safe relative URL from data payload."
  def url(%__MODULE__{data: data}) when is_map(data) do
    url = Map.get(data, "url") || Map.get(data, :url)

    if is_binary(url) and url != "" and String.starts_with?(url, "/") and
         not String.starts_with?(url, "//") do
      url
    else
      nil
    end
  end

  def url(_), do: nil

  @doc "Extracts icon from data payload or returns default."
  def icon(%__MODULE__{data: data}) when is_map(data) do
    Map.get(data, "icon") || Map.get(data, :icon) || "hero-bell"
  end

  def icon(_), do: "hero-bell"

  defp format_type_title(type) when is_binary(type) do
    type
    |> String.split(["\\", "."])
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_type_title(_), do: "Notification"
end
