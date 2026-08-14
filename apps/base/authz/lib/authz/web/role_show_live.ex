defmodule Bilimbi.Base.Authz.Web.RoleShowLive do
  @moduledoc """
  One role, its capabilities and the principals holding it.

  Ports Belimbing's `app/Base/Authz/Livewire/Roles/Show.php` for the read half;
  the edit and assignment actions it also carries are later slices of #99.

  A role outside the actor's tenant is `:not_found` rather than forbidden.
  `Authz.get_role/2` scopes the lookup, so a wrong id and another tenant's id
  are indistinguishable from here -- which is the point, since telling them
  apart would confirm the role exists.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {role_id, ""} -> load(socket, role_id)
      _ -> {:ok, not_found(socket)}
    end
  end

  defp load(socket, role_id) do
    case Authz.get_role(socket.assigns.current_scope.scope, role_id) do
      {:ok, details} ->
        {:ok,
         socket
         |> assign(:page_title, details.role.name)
         |> assign(:role, details.role)
         |> assign(:capabilities, Enum.sort(details.capabilities))
         |> assign(:principal_roles, details.principal_roles)}

      {:error, :not_found} ->
        {:ok, not_found(socket)}
    end
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "That role does not exist in this tenant.")
    |> push_navigate(to: ~p"/authz/roles")
  end

  defp scope_label(%{is_system: true}), do: "System"
  defp scope_label(%{company_id: nil}), do: "Unowned"
  defp scope_label(_role), do: "Custom"

  defp scope_kind(%{is_system: true}), do: :neutral
  defp scope_kind(%{company_id: nil}), do: :warning
  defp scope_kind(_role), do: :success

  defp principal_label(%{principal_type: :agent}), do: "Employee"
  defp principal_label(%{principal_type: :user}), do: "User"
  defp principal_label(%{principal_type: other}), do: to_string(other)
end
