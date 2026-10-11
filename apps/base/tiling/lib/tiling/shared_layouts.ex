defmodule Bilimbi.Base.Tiling.SharedLayouts do
  @moduledoc """
  Published workspaces for one company. Role codes filter visibility; an empty
  role list makes a workspace visible to everyone in that company. The company
  Settings scope is deliberate: shared layouts never inherit from a tenant.

  Publishing and deleting take the sealed tenancy scope and check
  `ui.workspace.publish`, the capability the shared-workspaces screen already
  requires. The company is the actor's company. A system actor names nobody
  and is refused. Listing stays a settings read; the screen's controls only
  present what this module decides.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tiling.SavedLayouts

  @key "ui.workspace.shared_layouts"
  @publish "ui.workspace.publish"

  @spec list(SettingsScope.t()) :: [map()]
  def list(%SettingsScope{type: :company} = scope) do
    case Settings.get(@key, scope) do
      entries when is_list(entries) -> Enum.filter(entries, &valid_entry?/1)
      _ -> []
    end
  end

  @spec visible(SettingsScope.t() | nil, [String.t()]) :: [map()]
  def visible(nil, _role_codes), do: []

  def visible(%SettingsScope{type: :company} = scope, role_codes) when is_list(role_codes) do
    Enum.filter(list(scope), fn entry ->
      entry["roles"] == [] or Enum.any?(entry["roles"], &(&1 in role_codes))
    end)
  end

  @spec fetch_visible(SettingsScope.t() | nil, String.t(), [String.t()]) ::
          {:ok, map()} | :error
  def fetch_visible(nil, _slug, _role_codes), do: :error

  def fetch_visible(%SettingsScope{type: :company} = scope, slug, role_codes) do
    case Enum.find(visible(scope, role_codes), &(&1["slug"] == slug)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @spec publish(Scope.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, map()}
          | {:error,
             :forbidden | :company_archived | :label | :tree | :roles | Ecto.Changeset.t()}
  def publish(%Scope{} = scope, label, tree, roles)
      when is_binary(label) and is_binary(tree) and is_list(roles) do
    with :ok <- authorize(scope),
         {:ok, settings_scope} <- company_settings_scope(scope),
         :ok <- writable(scope, settings_scope),
         {:ok, label} <- SavedLayouts.clean_label(label),
         {:ok, tree} <- SavedLayouts.clean_tree(tree),
         true <- Enum.all?(roles, &valid_role?/1) || {:error, :roles} do
      entries = list(settings_scope)
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
      with {:ok, _} <- Settings.put(@key, entries, settings_scope), do: {:ok, entry}
    end
  end

  @spec delete(Scope.t(), String.t()) ::
          :ok | {:error, :forbidden | :company_archived | Ecto.Changeset.t()}
  def delete(%Scope{} = scope, slug) when is_binary(slug) do
    with :ok <- authorize(scope),
         {:ok, settings_scope} <- company_settings_scope(scope),
         :ok <- writable(scope, settings_scope) do
      entries = Enum.reject(list(settings_scope), &(&1["slug"] == slug))
      with {:ok, _} <- Settings.put(@key, entries, settings_scope), do: :ok
    end
  end

  # The screen's route capability is presentation. This is the write: the
  # same `ui.workspace.publish` key, asked of the scope the edge sealed.
  # An anonymous system actor has no grant and is refused.
  defp authorize(scope) do
    case Authz.can(scope, @publish) do
      %{allowed: true} -> :ok
      %{allowed: false} -> {:error, :forbidden}
    end
  end

  # A shared layout is a company-scoped setting, and an archived company is
  # read-only: the Authz company directory answers for every Base write.
  defp writable(scope, %SettingsScope{type: :company, id: company_id}) do
    case Authz.company_writable(scope, company_id) do
      :ok -> :ok
      {:error, :company_archived} -> {:error, :company_archived}
      {:error, :company_not_found} -> {:error, :forbidden}
    end
  end

  defp company_settings_scope(scope) do
    case Scope.actor(scope) do
      %{company_id: company_id} when is_integer(company_id) and company_id > 0 ->
        {:ok, SettingsScope.company(company_id)}

      _actor ->
        {:error, :forbidden}
    end
  end

  defp valid_role?(code), do: is_binary(code) and Regex.match?(~r/^[a-z0-9_]+$/, code)

  defp valid_entry?(%{"slug" => slug, "label" => label, "tree" => tree, "roles" => roles})
       when is_binary(slug) and is_binary(label) and is_binary(tree) and is_list(roles),
       do: Enum.all?(roles, &valid_role?/1)

  defp valid_entry?(_), do: false
end
