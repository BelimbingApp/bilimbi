defmodule Bilimbi.Base.Tiling.Web.SharedLayoutsLive do
  @moduledoc "Company workspaces and their role audiences."

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tiling.Layout
  alias Bilimbi.Base.Tiling.SharedLayouts

  # This route mounts under ui.workspace.publish, and both write handlers
  # check that capability again before changing company settings.
  # delete-layout only opens the confirmation dialog; it writes nothing.
  @write_guard_opt_out ~w(publish-layout delete-layout confirm-delete-layout)

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope
    company_scope = SettingsScope.company(current_scope.user["company_id"])

    role_options =
      current_scope.scope
      |> Authz.list_roles()
      |> Enum.filter(&(&1.company_id in [nil, company_scope.id]))
      |> Enum.map(&{&1.name, &1.code})

    {:ok,
     socket
     |> assign(:page_title, gettext("Shared workspaces"))
     |> assign(:company_scope, company_scope)
     |> assign(:role_options, role_options)
     |> assign(:entries, SharedLayouts.list(company_scope))
     |> assign(:pending_delete, nil)
     |> assign(:form, to_form(%{"label" => "", "roles" => []}, as: :layout))}
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
    if allowed?(socket.assigns.current_scope, "ui.workspace.publish") do
      roles = params |> Map.get("roles", []) |> List.wrap() |> Enum.reject(&(&1 == ""))
      known = MapSet.new(socket.assigns.role_options, &elem(&1, 1))

      cond do
        not Enum.all?(roles, &MapSet.member?(known, &1)) ->
          {:noreply, put_flash(socket, :error, gettext("Choose role codes from this company."))}

        true ->
          case SharedLayouts.publish(
                 socket.assigns.company_scope,
                 Map.get(params, "label", ""),
                 Map.get(params, "tree", ""),
                 roles
               ) do
            {:ok, _entry} ->
              {:noreply,
               socket
               |> assign(:entries, SharedLayouts.list(socket.assigns.company_scope))
               |> put_flash(:success, gettext("Shared the workspace."))}

            {:error, _reason} ->
              {:noreply, put_flash(socket, :error, gettext("The workspace could not be shared."))}
          end
      end
    else
      {:noreply, put_flash(socket, :error, gettext("You cannot share workspaces."))}
    end
  end

  def handle_event("delete-layout", %{"slug" => slug}, socket) do
    if Enum.any?(socket.assigns.entries, &(&1["slug"] == slug)) do
      {:noreply, assign(socket, :pending_delete, slug)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel-delete-layout", _params, socket),
    do: {:noreply, assign(socket, :pending_delete, nil)}

  def handle_event("confirm-delete-layout", _params, socket) do
    slug = socket.assigns.pending_delete

    if is_binary(slug) and allowed?(socket.assigns.current_scope, "ui.workspace.publish") do
      case SharedLayouts.delete(socket.assigns.company_scope, slug) do
        :ok ->
          {:noreply,
           assign(socket,
             entries: SharedLayouts.list(socket.assigns.company_scope),
             pending_delete: nil
           )}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> assign(:pending_delete, nil)
           |> put_flash(:error, gettext("The shared workspace could not be deleted."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("You cannot manage shared workspaces."))}
    end
  end
end
