defmodule Bilimbi.Base.Authz.Web.FieldAccessLive do
  @moduledoc """
  Administration › Authorization › Field Access: which fields of which
  records the tenant's roles may see.

  Field access is the operator's prerogative, not a developer's: a
  restriction is runtime data an operator sets here, per tenant, by picking a
  table and a field from the installed catalog and the roles that still see
  it. Everyone else reads the field as `<.restricted>` on the record page, in
  grid columns and in the audit views, and may not write it
  (`Bilimbi.Base.Authz.put_field_restriction/4`). The picker never offers a
  field a module protected or every reader needs
  (`Authz.field_restriction_catalog/0`).

  The page is read-first: the table lists the current restrictions with the
  roles that see each field; the form below adds one or, when it names a
  field already restricted, replaces its roles. Each row's roles are edited
  in place through the same form, and removing a restriction confirms
  through the shared dialog. Every write re-asks Authz for
  `admin.authz.field.manage`, the capability the route is gated on, so a
  grant revoked while the page is open is refused.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.UI.Params

  @capability "admin.authz.field.manage"

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok,
     socket
     |> assign(:page_title, "Field Access")
     |> assign(:catalog, Authz.field_restriction_catalog())
     |> assign(:roles, Authz.list_roles(scope))
     |> assign(:editing, nil)
     |> assign(:pending_removal, nil)
     |> assign_form(%{"table_id" => "", "field_id" => "", "role_ids" => []})
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"restriction" => params}, socket) do
    {:noreply, assign_form(socket, normalize(params, socket))}
  end

  def handle_event("save", %{"restriction" => params}, socket) do
    params = normalize(params, socket)

    case LiveAuthorization.authorize_event(socket, @capability) do
      {:ok, socket} ->
        save(socket, params)

      {:denied, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.restrictions, &(&1.id == Params.positive_integer(id))) do
      nil ->
        {:noreply, socket}

      restriction ->
        {:noreply,
         socket
         |> assign(:editing, restriction.id)
         |> assign_form(%{
           "table_id" => restriction.table_id,
           "field_id" => restriction.field_id,
           "role_ids" => Enum.map(restriction.role_ids, &Integer.to_string/1)
         })}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, reset_form(socket)}
  end

  def handle_event("request_remove", %{"id" => id}, socket) do
    restriction = Enum.find(socket.assigns.restrictions, &(&1.id == Params.positive_integer(id)))
    {:noreply, assign(socket, :pending_removal, restriction)}
  end

  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, :pending_removal, nil)}
  end

  def handle_event("remove", _params, %{assigns: %{pending_removal: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("remove", _params, socket) do
    restriction = socket.assigns.pending_removal
    socket = assign(socket, :pending_removal, nil)

    case LiveAuthorization.authorize_event(socket, @capability) do
      {:ok, socket} ->
        case Authz.remove_field_restriction(socket.assigns.current_scope.scope, restriction.id) do
          {:ok, :removed} ->
            {:noreply,
             socket
             |> put_flash(
               :success,
               gettext("%{table} › %{field} is no longer restricted.",
                 table: restriction.table_label,
                 field: restriction.field_label
               )
             )
             |> reset_form()
             |> load()}

          {:ok, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("That restriction was already removed."))
             |> load()}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, gettext("The restriction could not be removed."))}
        end

      {:denied, socket} ->
        {:noreply, socket}
    end
  end

  defp save(socket, %{"table_id" => table_id, "field_id" => field_id, "role_ids" => role_ids}) do
    scope = socket.assigns.current_scope.scope
    ids = role_ids |> Enum.map(&Params.positive_integer/1) |> Enum.reject(&is_nil/1)

    case Authz.put_field_restriction(scope, table_id, field_id, ids) do
      {:ok, restriction} ->
        {:noreply,
         socket
         |> put_flash(:success, saved_message(restriction))
         |> reset_form()
         |> load()}

      {:error, :not_restrictable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Choose a table and one of its restrictable fields.")
         )}

      {:error, {:unknown_roles, _ids}} ->
        {:noreply, put_flash(socket, :error, gettext("Choose roles of this tenant."))}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You do not have permission to manage field access.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("The restriction could not be saved."))}
    end
  end

  defp load(socket) do
    case Authz.list_field_restrictions(socket.assigns.current_scope.scope) do
      {:ok, restrictions} -> assign(socket, :restrictions, restrictions)
      {:error, :forbidden} -> assign(socket, :restrictions, [])
    end
  end

  defp reset_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign_form(%{"table_id" => "", "field_id" => "", "role_ids" => []})
  end

  defp assign_form(socket, params) do
    socket
    |> assign(:form, to_form(params, as: :restriction))
    |> assign(:field_options, field_options(socket.assigns.catalog, params["table_id"]))
  end

  # A field of another table is not a choice once the table changes, and a
  # multi-select submits nothing at all when every box is clear.
  defp normalize(params, socket) do
    # While a row is being edited its table and field are fixed (and their
    # selects disabled, so the form does not send them): they come from the
    # row, and only the roles are the operator's input.
    {table_id, field_id} =
      case Enum.find(socket.assigns.restrictions, &(&1.id == socket.assigns.editing)) do
        nil -> {Map.get(params, "table_id", ""), Map.get(params, "field_id", "")}
        editing -> {editing.table_id, editing.field_id}
      end

    fields = field_options(socket.assigns.catalog, table_id) |> Enum.map(&elem(&1, 1))

    %{
      "table_id" => table_id,
      "field_id" => if(field_id in fields, do: field_id, else: ""),
      "role_ids" => params |> Map.get("role_ids", []) |> List.wrap() |> Enum.reject(&(&1 == ""))
    }
  end

  defp field_options(catalog, table_id) do
    case Enum.find(catalog, &(&1.id == table_id)) do
      nil -> []
      table -> Enum.map(table.fields, &{&1.label, &1.id})
    end
  end

  defp table_options(catalog), do: Enum.map(catalog, &{&1.label, &1.id})

  defp role_options(roles), do: Enum.map(roles, &{&1.name, Integer.to_string(&1.id)})

  defp saved_message(%{role_names: []} = restriction) do
    gettext("%{table} › %{field} is restricted to no role.",
      table: restriction.table_label,
      field: restriction.field_label
    )
  end

  defp saved_message(restriction) do
    gettext("%{table} › %{field} is restricted to %{roles}.",
      table: restriction.table_label,
      field: restriction.field_label,
      roles: Enum.join(restriction.role_names, ", ")
    )
  end
end
