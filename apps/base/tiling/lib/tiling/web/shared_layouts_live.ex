defmodule Bilimbi.Base.Tiling.Web.SharedLayoutsLive do
  @moduledoc "Company workspaces and their role audiences."

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tiling.Layout
  alias Bilimbi.Base.Tiling.SharedLayouts
  alias Bilimbi.Base.UI.ListColumns

  # The route mounts under ui.workspace.publish. Publishing and deleting are
  # SharedLayouts writes: they take the sealed scope and check that same
  # capability. These handlers only present the outcome. delete-layout opens
  # the confirmation and writes nothing.
  @write_guard_opt_out ~w(publish-layout delete-layout confirm-delete-layout grid)
  @builtins [
    %{id: "label", label: "Name"},
    %{id: "audience", label: "Audience"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns.current_scope.user["company_id"] do
      nil ->
        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("Shared workspaces belong to a company; this account has none.")
         )
         |> push_navigate(to: ~p"/workspace")}

      company_id ->
        {:ok, mount_company(socket, SettingsScope.company(company_id))}
    end
  end

  defp mount_company(socket, company_scope) do
    current_scope = socket.assigns.current_scope
    entries = SharedLayouts.list(company_scope)

    role_options =
      current_scope.scope
      |> Authz.list_roles()
      |> Enum.filter(&(&1.company_id in [nil, company_scope.id]))
      |> Enum.map(&{&1.name, &1.code})

    socket
    |> assign(:page_title, gettext("Shared workspaces"))
    |> assign(:company_scope, company_scope)
    |> assign(:columns, ListColumns.mount("shared-workspaces", @builtins))
    |> assign(:role_options, role_options)
    |> assign_entries(entries)
    |> assign(:pending_delete, nil)
    |> assign(:form, to_form(%{"label" => "", "roles" => []}, as: :layout))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tree = params["t"] || ""
    tree = if match?({:ok, %Layout{}}, Layout.decode(tree)), do: tree, else: ""

    {:noreply,
     socket
     |> assign(:tree, tree)
     |> assign(:form, to_form(%{"label" => "", "roles" => [], "tree" => tree}, as: :layout))}
  end

  @impl true
  def handle_event("publish-layout", %{"layout" => params}, socket) do
    roles = params |> Map.get("roles", []) |> List.wrap() |> Enum.reject(&(&1 == ""))
    known = MapSet.new(socket.assigns.role_options, &elem(&1, 1))

    if Enum.all?(roles, &MapSet.member?(known, &1)) do
      publish(socket, params, roles)
    else
      {:noreply, put_flash(socket, :error, gettext("Choose role codes from this company."))}
    end
  end

  def handle_event("delete-layout", %{"slug" => slug}, socket) do
    if Enum.any?(socket.assigns.entries, &(&1["slug"] == slug)) do
      {:noreply, assign(socket, :pending_delete, slug)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      _outcome -> {:noreply, socket}
    end
  end

  def handle_event("cancel-delete-layout", _params, socket),
    do: {:noreply, assign(socket, :pending_delete, nil)}

  def handle_event("confirm-delete-layout", _params, socket) do
    case socket.assigns.pending_delete do
      slug when is_binary(slug) ->
        case SharedLayouts.delete(socket.assigns.current_scope.scope, slug) do
          :ok ->
            {:noreply,
             socket
             |> assign_entries(SharedLayouts.list(socket.assigns.company_scope))
             |> assign(:pending_delete, nil)}

          {:error, :forbidden} ->
            {:noreply,
             socket
             |> assign(:pending_delete, nil)
             |> put_flash(:error, gettext("You cannot manage shared workspaces."))}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:pending_delete, nil)
             |> put_flash(:error, gettext("The shared workspace could not be deleted."))}
        end

      _missing ->
        {:noreply, put_flash(socket, :error, gettext("You cannot manage shared workspaces."))}
    end
  end

  defp publish(socket, params, roles) do
    case SharedLayouts.publish(
           socket.assigns.current_scope.scope,
           Map.get(params, "label", ""),
           Map.get(params, "tree", ""),
           roles
         ) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> assign_entries(SharedLayouts.list(socket.assigns.company_scope))
         |> put_flash(:success, gettext("Shared the workspace."))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot share workspaces."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("The workspace could not be shared."))}
    end
  end

  defp assign_entries(socket, entries) do
    socket
    |> assign(:entries, entries)
    |> assign(:columns, ListColumns.load(socket.assigns.columns, entries, & &1["slug"]))
  end
end
