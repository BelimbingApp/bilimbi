defmodule Bilimbi.Core.User.DatabaseQuery do
  @moduledoc """
  Ecto schema for `user_database_queries`.

  Stores user-defined, parameterized SQL queries that render as browsable, pinnable pages.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Bilimbi.Base.Repo

  @type t :: %__MODULE__{}

  schema "user_database_queries" do
    field :user_id, :integer
    field :name, :string
    field :slug, :string
    field :prompt, :string
    field :sql_query, :string
    field :description, :string
    field :icon, :string

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @fields [:user_id, :name, :slug, :prompt, :sql_query, :description, :icon]
  @required_fields [:user_id, :name, :sql_query]

  def changeset(query, attrs) do
    query
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 150)
    |> validate_length(:slug, max: 200)
    |> maybe_generate_slug()
    |> unique_constraint([:user_id, :slug], name: :user_database_queries_user_id_slug_unique)
  end

  defp maybe_generate_slug(changeset) do
    case {get_field(changeset, :slug), get_field(changeset, :name),
          get_field(changeset, :user_id)} do
      {slug, _, _} when is_binary(slug) and slug != "" ->
        changeset

      {_, name, user_id} when is_binary(name) and name != "" and is_integer(user_id) ->
        put_change(changeset, :slug, generate_slug(user_id, name))

      _ ->
        changeset
    end
  end

  @doc """
  Generates a unique slug for a given query title and user ID.
  """
  @spec generate_slug(pos_integer(), String.t()) :: String.t()
  def generate_slug(user_id, name) when is_integer(user_id) and is_binary(name) do
    base_slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^\w\s-]/u, "")
      |> String.replace(~r/[\s_]+/u, "-")
      |> String.replace(~r/^-+|-+$/u, "")
      |> case do
        "" -> "query"
        slug -> slug
      end

    find_unique_slug(user_id, base_slug, base_slug, 2)
  end

  defp find_unique_slug(user_id, base_slug, current_slug, suffix) do
    exists? =
      from(q in __MODULE__,
        where: q.user_id == ^user_id and q.slug == ^current_slug
      )
      |> Repo.exists?()

    if exists? do
      find_unique_slug(user_id, base_slug, "#{base_slug}-#{suffix}", suffix + 1)
    else
      current_slug
    end
  end
end
