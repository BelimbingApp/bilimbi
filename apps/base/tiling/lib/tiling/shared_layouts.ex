defmodule Bilimbi.Base.Tiling.SharedLayouts do
  @moduledoc """
  Published workspaces for one company. Role codes filter visibility; an empty
  role list makes a workspace visible to everyone in that company. The company
  Settings scope is deliberate: shared layouts never inherit from a tenant.
  """

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Tiling.SavedLayouts

  @key "ui.workspace.shared_layouts"

  @spec list(Scope.t()) :: [map()]
  def list(%Scope{type: :company} = scope) do
    case Settings.get(@key, scope) do
      entries when is_list(entries) -> Enum.filter(entries, &valid_entry?/1)
      _ -> []
    end
  end

  @spec visible(Scope.t(), [String.t()]) :: [map()]
  def visible(%Scope{type: :company} = scope, role_codes) when is_list(role_codes) do
    Enum.filter(list(scope), fn entry ->
      entry["roles"] == [] or Enum.any?(entry["roles"], &(&1 in role_codes))
    end)
  end

  @spec fetch_visible(Scope.t(), String.t(), [String.t()]) :: {:ok, map()} | :error
  def fetch_visible(%Scope{type: :company} = scope, slug, role_codes) do
    case Enum.find(visible(scope, role_codes), &(&1["slug"] == slug)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec publish(Scope.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, map()} | {:error, :label | :tree | :roles | Ecto.Changeset.t()}
  def publish(%Scope{type: :company} = scope, label, tree, roles)
      when is_binary(label) and is_binary(tree) and is_list(roles) do
    with {:ok, label} <- SavedLayouts.clean_label(label),
         {:ok, tree} <- SavedLayouts.clean_tree(tree),
         true <- Enum.all?(roles, &valid_role?/1) || {:error, :roles} do
      entries = list(scope)
      roles = Enum.uniq(roles)

      entry =
        case Enum.find(entries, &(&1["label"] == label)) do
          nil ->
            %{
              "slug" => SavedLayouts.unique_slug(SavedLayouts.slug(label), entries),
              "label" => label,
              "layout" => "dwindle",
              "tree" => tree,
              "roles" => roles
            }

          prior ->
            %{prior | "tree" => tree, "roles" => roles}
        end

      entries = Enum.reject(entries, &(&1["slug"] == entry["slug"])) ++ [entry]
      with {:ok, _} <- Settings.put(@key, entries, scope), do: {:ok, entry}
    end
  end

  @spec delete(Scope.t(), String.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete(%Scope{type: :company} = scope, slug) when is_binary(slug) do
    entries = Enum.reject(list(scope), &(&1["slug"] == slug))
    with {:ok, _} <- Settings.put(@key, entries, scope), do: :ok
  end

  defp valid_role?(code), do: is_binary(code) and Regex.match?(~r/^[a-z0-9_]+$/, code)

  defp valid_entry?(%{"slug" => slug, "label" => label, "tree" => tree, "roles" => roles})
       when is_binary(slug) and is_binary(label) and is_binary(tree) and is_list(roles),
       do: Enum.all?(roles, &valid_role?/1)

  defp valid_entry?(_), do: false
end
