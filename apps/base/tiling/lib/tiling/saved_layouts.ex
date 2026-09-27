defmodule Bilimbi.Base.Tiling.SavedLayouts do
  @moduledoc """
  The tiled layouts one account has saved, and which of them opens first.

  Both live in the account's own Settings rows, the way the dashboard keeps
  its widget order: `ui.workspace.layouts` is the list and
  `ui.workspace.default` names one of them by slug. A saved layout is a
  plain map so it stores as JSON:

      %{"slug" => "orders-desk", "label" => "Orders desk",
        "layout" => "dwindle", "tree" => "h.5(/companies,/users)"}

  `tree` is `Bilimbi.Base.Tiling.Layout.encode/1` output, kept as written,
  so a layout that points at a page the account can no longer open is still
  listed; the workspace decides what to show in that tile.

  The slug is derived from the label once and never changes, so a link to
  `/workspace/<slug>` survives a rename. Every function takes the account's
  `Bilimbi.Base.Settings.Scope`, built by the caller at the edge, and every
  write goes through the Repo, so it is audited like any other.
  """

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Tiling.Layout

  @layouts_key "ui.workspace.layouts"
  @default_key "ui.workspace.default"
  @max_label 60
  @reserved_slugs ["shared-layouts"]

  @type entry :: %{
          required(String.t()) => String.t()
        }

  @doc "Every saved layout, in the order they were saved."
  @spec list(Scope.t()) :: [entry()]
  def list(%Scope{type: :user} = scope) do
    case Settings.get(@layouts_key, scope) do
      entries when is_list(entries) -> Enum.filter(entries, &entry?/1)
      _other -> []
    end
  end

  @doc "The saved layout with this slug."
  @spec fetch(Scope.t(), String.t()) :: {:ok, entry()} | :error
  def fetch(%Scope{} = scope, slug) when is_binary(slug) do
    case Enum.find(list(scope), &(&1["slug"] == slug)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc "The slug `/workspace` opens, or nil when none is saved as the default."
  @spec default_slug(Scope.t()) :: String.t() | nil
  def default_slug(%Scope{} = scope) do
    case Settings.get(@default_key, scope) do
      "" -> nil
      slug when is_binary(slug) -> if match?({:ok, _}, fetch(scope, slug)), do: slug
      _other -> nil
    end
  end

  @doc """
  Saves `tree` under `label`. A label already in use replaces that layout's
  tree and keeps its slug; a new label gets a slug of its own. Passing a mode
  saves that mode with the tree. Without one, a replacement keeps its mode
  and a new layout starts in dwindle mode.
  """
  @spec save(Scope.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, entry()} | {:error, :label | :tree | :layout | Ecto.Changeset.t()}
  def save(%Scope{type: :user} = scope, label, tree, mode \\ nil)
      when is_binary(label) and is_binary(tree) do
    with true <- mode in [nil, "dwindle", "master"],
         {:ok, label} <- clean_label(label),
         {:ok, tree} <- clean_tree(tree) do
      entries = list(scope)
      slug = unique_slug(slug(label), entries)

      {entries, entry} =
        case Enum.find_index(entries, &(&1["label"] == label)) do
          nil ->
            entry = %{
              "slug" => slug,
              "label" => label,
              "layout" => mode || "dwindle",
              "tree" => tree
            }

            {entries ++ [entry], entry}

          index ->
            entry = Enum.at(entries, index)
            entry = entry |> Map.put("tree", tree) |> Map.put("layout", mode || entry["layout"])
            {List.replace_at(entries, index, entry), entry}
        end

      with {:ok, _} <- Settings.put(@layouts_key, entries, scope), do: {:ok, entry}
    else
      false -> {:error, :layout}
      other -> other
    end
  end

  @doc "Gives the layout with `slug` a new label; the slug stays."
  @spec rename(Scope.t(), String.t(), String.t()) ::
          {:ok, entry()} | {:error, :label | :not_found | Ecto.Changeset.t()}
  def rename(%Scope{type: :user} = scope, slug, label)
      when is_binary(slug) and is_binary(label) do
    with {:ok, label} <- clean_label(label),
         {:ok, entry} <- fetch(scope, slug) do
      entry = Map.put(entry, "label", label)
      entries = Enum.map(list(scope), &if(&1["slug"] == slug, do: entry, else: &1))

      with {:ok, _} <- Settings.put(@layouts_key, entries, scope), do: {:ok, entry}
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  @doc "Sets the tiling mode and its converted tree for one saved layout."
  @spec set_layout(Scope.t(), String.t(), String.t(), String.t()) ::
          {:ok, entry()} | {:error, :layout | :tree | :not_found | Ecto.Changeset.t()}
  def set_layout(%Scope{type: :user} = scope, slug, mode, tree)
      when is_binary(slug) and is_binary(mode) and is_binary(tree) do
    with true <- mode in ["dwindle", "master"],
         {:ok, tree} <- clean_tree(tree),
         {:ok, entry} <- fetch(scope, slug) do
      entry = entry |> Map.put("layout", mode) |> Map.put("tree", tree)
      entries = Enum.map(list(scope), &if(&1["slug"] == slug, do: entry, else: &1))
      with {:ok, _} <- Settings.put(@layouts_key, entries, scope), do: {:ok, entry}
    else
      false -> {:error, :layout}
      :error -> {:error, :not_found}
      other -> other
    end
  end

  @doc "Forgets the layout with `slug`, and the default if it named it."
  @spec delete(Scope.t(), String.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete(%Scope{type: :user} = scope, slug) when is_binary(slug) do
    entries = Enum.reject(list(scope), &(&1["slug"] == slug))

    with {:ok, _} <- Settings.put(@layouts_key, entries, scope) do
      if Settings.get(@default_key, scope) == slug, do: set_default(scope, nil), else: :ok
    end
  end

  @doc "Makes the layout with `slug` the one `/workspace` opens; `nil` clears it."
  @spec set_default(Scope.t(), String.t() | nil) ::
          :ok | {:error, :not_found | Ecto.Changeset.t()}
  # Clearing removes the override: the settings column cannot hold an empty
  # string, and an absent row already reads as the definition's default.
  def set_default(%Scope{type: :user} = scope, nil), do: Settings.delete(@default_key, scope)

  def set_default(%Scope{type: :user} = scope, slug) when is_binary(slug) do
    with {:ok, _} <- fetch(scope, slug),
         {:ok, _} <- Settings.put(@default_key, slug, scope) do
      :ok
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  @doc "The URL slug for a label: lower-case words joined by hyphens."
  @spec slug(String.t()) :: String.t()
  def slug(label) when is_binary(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "layout"
      slug -> slug
    end
  end

  @doc "The first of `base`, `base-2`, `base-3`, ... that no entry and no workspace route uses."
  @spec unique_slug(String.t(), [map()]) :: String.t()
  def unique_slug(base, entries) do
    taken = MapSet.new(entries, & &1["slug"]) |> MapSet.union(MapSet.new(@reserved_slugs))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  @doc "A label with whitespace collapsed, when it is one to 60 bytes."
  @spec clean_label(String.t()) :: {:ok, String.t()} | {:error, :label}
  def clean_label(label) do
    case label |> String.trim() |> String.replace(~r/\s+/u, " ") do
      "" -> {:error, :label}
      label when byte_size(label) > @max_label -> {:error, :label}
      label -> {:ok, label}
    end
  end

  @doc "The encoded tree, when it decodes to at least one tile."
  @spec clean_tree(String.t()) :: {:ok, String.t()} | {:error, :tree}
  def clean_tree(tree) do
    case Layout.decode(tree) do
      {:ok, %Layout{root: nil}} -> {:error, :tree}
      {:ok, _layout} -> {:ok, tree}
      :error -> {:error, :tree}
    end
  end

  defp entry?(%{"slug" => slug, "label" => label, "tree" => tree})
       when is_binary(slug) and is_binary(label) and is_binary(tree),
       do: true

  defp entry?(_other), do: false
end
