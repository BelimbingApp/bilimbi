defmodule Bilimbi.Core.User.Pin do
  @moduledoc """
  Ecto schema and normalization for user-pinned sidebar items (`user_pins`).

  Pins are identified per-user by their normalized URL hash (`url_hash`),
  ensuring idempotency across relative vs absolute paths and parameter ordering.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          user_id: pos_integer() | nil,
          label: String.t() | nil,
          url: String.t() | nil,
          url_hash: String.t() | nil,
          icon: String.t() | nil,
          sort_order: integer() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id
  schema "user_pins" do
    field :user_id, :integer
    field :label, :string
    field :url, :string
    field :url_hash, :string
    field :icon, :string
    field :sort_order, :integer, default: 0

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :naive_datetime)
  end

  @doc false
  def changeset(pin, attrs) do
    pin
    |> cast(attrs, [:user_id, :label, :url, :icon, :sort_order])
    |> validate_required([:user_id, :label, :url])
    |> validate_length(:label, max: 150)
    |> validate_length(:url, max: 500)
    |> validate_length(:icon, max: 100)
    |> normalize_attributes()
    |> unique_constraint([:user_id, :url_hash], name: :user_pins_user_id_url_hash_unique)
  end

  defp normalize_attributes(changeset) do
    changeset =
      case get_change(changeset, :label) do
        nil -> changeset
        label when is_binary(label) -> put_change(changeset, :label, normalize_label(label))
      end

    case get_change(changeset, :url) do
      nil ->
        changeset

      url when is_binary(url) ->
        normalized_url = normalize_url(url)
        hash = hash_url(url)

        changeset
        |> put_change(:url, normalized_url)
        |> put_change(:url_hash, hash)
    end
  end

  @doc """
  Normalizes a label by extracting the last non-empty segment of a breadcrumb path.
  """
  @spec normalize_label(String.t()) :: String.t()
  def normalize_label(label) when is_binary(label) do
    segments =
      label
      |> String.split("/")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case List.last(segments) do
      nil -> String.trim(label)
      leaf -> leaf
    end
  end

  @doc """
  Normalizes a URL by keeping only the canonical path and deterministically sorted query string.
  """
  @spec normalize_url(String.t()) :: String.t()
  def normalize_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    path = normalize_path(uri.path || url)

    case uri.query do
      nil ->
        path

      "" ->
        path

      query when is_binary(query) ->
        sorted_query =
          query
          |> URI.decode_query()
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> URI.encode_query()

        if sorted_query == "", do: path, else: "#{path}?#{sorted_query}"
    end
  end

  defp normalize_path(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" ->
        "/"

      String.starts_with?(trimmed, "/") ->
        if trimmed == "/", do: "/", else: String.trim_trailing(trimmed, "/")

      true ->
        normalized = "/" <> trimmed
        if normalized == "/", do: "/", else: String.trim_trailing(normalized, "/")
    end
  end

  @doc """
  Computes the 32-character lowercase MD5 hash of a normalized URL.
  """
  @spec hash_url(String.t()) :: String.t()
  def hash_url(url) when is_binary(url) do
    url
    |> normalize_url()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end
end
