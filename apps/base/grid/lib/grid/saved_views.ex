defmodule Bilimbi.Base.Grid.SavedViews do
  @moduledoc """
  The grid views an account saved for itself and the ones shared with its
  company: a table, its columns, lenses, zoom, sort, search and grouping,
  under a label, as `Bilimbi.Base.Tiling.SavedLayouts` keeps workspace
  layouts.

  Own views live in the account's `ui.grid.views` setting at user scope;
  shared views live in `ui.grid.shared_views` at company scope, so every
  account of the company reads them and writing one needs the company
  settings capability, which the page checks. A shared view carries the
  role codes it is limited to; an empty list means everyone in the
  company, as `Bilimbi.Base.Tiling.SharedLayouts` limits workspaces. Both
  are plain JSON entries:

      %{"slug" => "open-orders", "label" => "Open orders",
        "table" => "orders", "view" => %{"columns" => [...], ...},
        "roles" => ["reviewer"]}

  A slug is derived from the label once and never changes, so
  `/grid/orders?v=open-orders` survives a rename; a shared view is addressed
  as `v=shared:open-orders`. Every write goes through the Repo and is
  audited like any other.
  """

  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope

  @own_key "ui.grid.views"
  @shared_key "ui.grid.shared_views"
  @max_label 60
  @shared_prefix "shared:"

  @type entry :: %{required(String.t()) => term()}

  @doc "The setting keys, own then shared."
  @spec keys() :: {String.t(), String.t()}
  def keys, do: {@own_key, @shared_key}

  @doc "Every own view of a table, in the order saved."
  @spec list_own(Scope.t(), String.t()) :: [entry()]
  def list_own(%Scope{type: :user} = scope, table), do: read(@own_key, scope, table)

  @doc "Every view shared with the company for a table, whatever its role audience."
  @spec list_shared(Scope.t(), String.t()) :: [entry()]
  def list_shared(%Scope{type: :company} = scope, table), do: read(@shared_key, scope, table)

  @doc """
  The shared views of a table an account holding `role_codes` may open:
  those limited to no role, and those limited to a role it holds.
  """
  @spec visible_shared(Scope.t() | nil, String.t(), [String.t()]) :: [entry()]
  def visible_shared(nil, _table, _role_codes), do: []

  def visible_shared(%Scope{type: :company} = scope, table, role_codes)
      when is_list(role_codes) do
    Enum.filter(list_shared(scope, table), &audience?(&1, role_codes))
  end

  defp audience?(entry, role_codes) do
    case roles(entry) do
      [] -> true
      roles -> Enum.any?(roles, &(&1 in role_codes))
    end
  end

  @doc "The role codes a shared entry is limited to; `[]` is everyone in the company."
  @spec roles(entry()) :: [String.t()]
  def roles(entry), do: entry |> Map.get("roles", []) |> Enum.filter(&is_binary/1)

  @doc """
  The view a `v` param names: an own slug, or `shared:<slug>` for a shared
  one this account may open, given the role codes it holds.
  """
  @spec fetch(Scope.t(), Scope.t() | nil, String.t(), String.t(), [String.t()]) ::
          {:ok, entry(), :own | :shared} | :error
  def fetch(own, shared, table, reference, role_codes \\ [])

  def fetch(%Scope{type: :user}, shared, table, @shared_prefix <> slug, role_codes) do
    case Enum.find(visible_shared(shared, table, role_codes), &(&1["slug"] == slug)) do
      nil -> :error
      entry -> {:ok, entry, :shared}
    end
  end

  def fetch(%Scope{type: :user} = own, _shared, table, slug, _role_codes) when is_binary(slug) do
    case Enum.find(list_own(own, table), &(&1["slug"] == slug)) do
      nil -> :error
      entry -> {:ok, entry, :own}
    end
  end

  @doc "The `v` param that opens an entry."
  @spec reference(entry(), :own | :shared) :: String.t()
  def reference(%{"slug" => slug}, :own), do: slug
  def reference(%{"slug" => slug}, :shared), do: @shared_prefix <> slug

  @doc """
  Saves `view` under `label` for the account (`:own`) or the company
  (`:shared`), a shared view limited to `roles` (none means everyone in
  the company). A label already used for that table replaces the view and
  keeps its slug; a new label gets a slug of its own.
  """
  @spec save(Scope.t(), :own | :shared, String.t(), View.t(), [String.t()]) ::
          {:ok, entry()} | {:error, :label | :roles | Ecto.Changeset.t()}
  def save(scope, kind, label, view, roles \\ [])

  def save(%Scope{} = scope, kind, label, %View{} = view, roles)
      when kind in [:own, :shared] and is_binary(label) and is_list(roles) do
    key = key(kind)
    roles = if kind == :shared, do: Enum.uniq(roles), else: []

    with {:ok, label} <- clean_label(label),
         true <- Enum.all?(roles, &role?/1) || {:error, :roles} do
      entries = read_all(key, scope)
      table = view.table
      slug = unique_slug(slug(label), entries)

      {entries, entry} =
        case Enum.find_index(entries, &(&1["label"] == label and &1["table"] == table)) do
          nil ->
            entry =
              %{"slug" => slug, "label" => label, "table" => table, "view" => View.to_map(view)}
              |> put_roles(kind, roles)

            {entries ++ [entry], entry}

          index ->
            entry =
              entries
              |> Enum.at(index)
              |> Map.put("view", View.to_map(view))
              |> put_roles(kind, roles)

            {List.replace_at(entries, index, entry), entry}
        end

      case Settings.put(key, entries, scope) do
        {:ok, _stored} -> {:ok, entry}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc "Deletes the view with this slug for this table from the account's or the company's list."
  @spec delete(Scope.t(), :own | :shared, String.t(), String.t()) :: :ok | :error
  def delete(%Scope{} = scope, kind, table, slug) when kind in [:own, :shared] do
    key = key(kind)
    entries = read_all(key, scope)

    case Enum.reject(entries, &(&1["slug"] == slug and &1["table"] == table)) do
      ^entries ->
        :error

      remaining ->
        {:ok, _stored} = Settings.put(key, remaining, scope)
        :ok
    end
  end

  @doc "The saved entry's view."
  @spec view(entry()) :: View.t()
  def view(%{"view" => map, "table" => table} = entry) when is_map(map) do
    %{View.from_map(Map.put(map, "table", table)) | slug: entry["slug"]}
  end

  defp key(:own), do: @own_key
  defp key(:shared), do: @shared_key

  defp put_roles(entry, :shared, roles), do: Map.put(entry, "roles", roles)
  defp put_roles(entry, :own, _roles), do: entry

  defp role?(code), do: is_binary(code) and Regex.match?(~r/^[a-z0-9_]+$/, code)

  defp read(key, scope, table), do: key |> read_all(scope) |> Enum.filter(&(&1["table"] == table))

  defp read_all(key, scope) do
    case Settings.get(key, scope) do
      entries when is_list(entries) -> Enum.filter(entries, &entry?/1)
      _other -> []
    end
  end

  defp entry?(%{"slug" => slug, "label" => label, "table" => table, "view" => view} = entry)
       when is_binary(slug) and is_binary(label) and is_binary(table) and is_map(view) do
    case Map.get(entry, "roles", []) do
      roles when is_list(roles) -> Enum.all?(roles, &role?/1)
      _other -> false
    end
  end

  defp entry?(_other), do: false

  defp clean_label(label) do
    case label |> String.trim() |> String.replace(~r/\s+/, " ") do
      "" -> {:error, :label}
      trimmed when byte_size(trimmed) > @max_label -> {:error, :label}
      trimmed -> {:ok, trimmed}
    end
  end

  defp slug(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "view"
      slug -> String.slice(slug, 0, 40)
    end
  end

  defp unique_slug(slug, entries) do
    taken = MapSet.new(entries, & &1["slug"])

    if MapSet.member?(taken, slug) do
      Enum.find_value(2..999, fn n ->
        if not MapSet.member?(taken, "#{slug}-#{n}"), do: "#{slug}-#{n}"
      end)
    else
      slug
    end
  end
end
