defmodule Bilimbi.Base.Authz.Web.FieldRestrictionsLive do
  @moduledoc """
  Administration › Authorization › Field Restrictions: which fields of which
  records are restricted for which roles.

  Every field is visible by default. A restriction is runtime data an
  operator sets here, per tenant, naming the roles a field is restricted
  for; a reader holding any of those roles reads it as `<.restricted>` on
  the record page, in grid columns and in the audit views, and may not write
  it (`Bilimbi.Base.Authz.put_field_restrictions/3`). The dialog never
  offers a field a module protected or every reader needs
  (`Authz.field_restriction_catalog/0`).

  The page is table-first, like Roles: the table lists the current
  restrictions, one row per field, and the header's primary action opens the
  restrict dialog. The dialog asks in the order an operator thinks: the
  roles to restrict, then the tables, then the fields of those tables, all
  three multiple and each shown as chips that can be removed in place. It
  reads the choice back in one sentence before it is saved. Several fields
  restricted together commit as one transaction and one row each. A row's
  roles are changed in a second, smaller dialog, which also offers to
  remove the restriction; removing, from the row or from that dialog,
  confirms through the shared dialog. Saving with no role left is not
  offered: the dialog says to remove the restriction instead, so a
  restriction never silently becomes one for nobody. Every write re-asks
  Authz for
  `admin.authz.field.manage`, the capability the route is gated on, so a
  grant revoked while the page is open is refused.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.UI.Params

  @capability "admin.authz.field.manage"

  # A field is picked as `table_id.field_id`, the subject spelling the audit
  # action already uses; a table id carries no dot.
  @separator "."

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    {:ok,
     socket
     |> assign(:page_title, "Field Restrictions")
     |> assign(:catalog, Authz.field_restriction_catalog())
     |> assign(:roles, Authz.list_roles(scope))
     |> assign(:dialog, nil)
     |> assign(:pending_removal, nil)
     |> assign_form(blank_params())
     |> load()}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> assign(:dialog, :add)
     |> assign_form(blank_params())}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case find_restriction(socket, id) do
      nil ->
        {:noreply, socket}

      restriction ->
        {:noreply,
         socket
         |> clear_flash()
         |> assign(:dialog, {:edit, restriction})
         |> assign_form(%{"role_ids" => Enum.map(restriction.role_ids, &Integer.to_string/1)})}
    end
  end

  def handle_event("close_dialog", _params, socket) do
    {:noreply, close_dialog(socket)}
  end

  def handle_event("validate", %{"restriction" => params}, socket) do
    {:noreply, assign_form(socket, normalize(params, socket))}
  end

  # A chip's remove button names the input and the value; the form is the
  # same one the pickers post, so dropping the value is a validate without
  # the browser's help.
  def handle_event("deselect", %{"name" => name, "option" => value}, socket) do
    params = socket.assigns.form.params

    case picker(name) do
      nil ->
        {:noreply, socket}

      key ->
        kept = params |> Map.get(key, []) |> List.delete(value)
        {:noreply, assign_form(socket, normalize(Map.put(params, key, kept), socket))}
    end
  end

  def handle_event("save", %{"restriction" => params}, socket) do
    params = normalize(params, socket)

    case LiveAuthorization.authorize_event(socket, @capability) do
      {:ok, socket} -> save(socket, params)
      {:denied, socket} -> {:noreply, socket}
    end
  end

  # Asked from the list or from the edit dialog; the edit dialog closes so
  # the confirmation is the one dialog open.
  def handle_event("request_remove", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> close_dialog()
     |> assign(:pending_removal, find_restriction(socket, id))}
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
               gettext("%{field} is no longer restricted.", field: subject(restriction))
             )
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

  # --- writes ----------------------------------------------------------------

  defp save(%{assigns: %{dialog: {:edit, restriction}}} = socket, params) do
    scope = socket.assigns.current_scope.scope

    case Authz.put_field_restriction(
           scope,
           restriction.table_id,
           restriction.field_id,
           role_ids(params)
         ) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:success, saved_message([saved]))
         |> close_dialog()
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refusal(reason))}
    end
  end

  defp save(socket, params) do
    scope = socket.assigns.current_scope.scope

    case Authz.put_field_restrictions(scope, fields(params), role_ids(params)) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:success, saved_message(saved))
         |> close_dialog()
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refusal(reason))}
    end
  end

  defp refusal(:not_restrictable),
    do: gettext("Choose fields the catalog offers; one of these is no longer restrictable.")

  defp refusal({:unknown_roles, _ids}), do: gettext("Choose roles of this tenant.")

  defp refusal(:forbidden),
    do: gettext("You do not have permission to manage field restrictions.")

  defp refusal(_reason), do: gettext("The restriction could not be saved.")

  # --- state -----------------------------------------------------------------

  defp load(socket) do
    case Authz.list_field_restrictions(socket.assigns.current_scope.scope) do
      {:ok, restrictions} -> assign(socket, :restrictions, restrictions)
      {:error, :forbidden} -> assign(socket, :restrictions, [])
    end
  end

  defp close_dialog(socket) do
    socket
    |> assign(:dialog, nil)
    |> assign_form(blank_params())
  end

  defp find_restriction(socket, id) do
    Enum.find(socket.assigns.restrictions, &(&1.id == Params.positive_integer(id)))
  end

  defp blank_params, do: %{"role_ids" => [], "table_ids" => [], "field_keys" => []}

  defp assign_form(socket, params) do
    params = Map.merge(blank_params(), params)
    catalog = socket.assigns.catalog

    socket
    |> assign(:form, to_form(params, as: :restriction))
    |> assign(:field_options, field_options(catalog, params["table_ids"]))
    |> assign(
      :chosen_roles,
      chosen_labels(role_options(socket.assigns.roles), params["role_ids"])
    )
    |> assign(:chosen_fields, chosen_field_labels(catalog, params["field_keys"]))
  end

  # A multi-select submits nothing at all when every box is clear, and a
  # field of a table no longer chosen is not a choice.
  defp normalize(params, socket) do
    table_ids = list(params, "table_ids")
    offered = socket.assigns.catalog |> field_options(table_ids) |> Enum.map(&elem(&1, 1))

    %{
      "role_ids" => list(params, "role_ids"),
      "table_ids" => table_ids,
      "field_keys" => params |> list("field_keys") |> Enum.filter(&(&1 in offered))
    }
  end

  defp list(params, key) do
    params |> Map.get(key, []) |> List.wrap() |> Enum.reject(&(&1 == "")) |> Enum.uniq()
  end

  # The input name a chip reports back, mapped to the form key it belongs to.
  defp picker("restriction[role_ids][]"), do: "role_ids"
  defp picker("restriction[table_ids][]"), do: "table_ids"
  defp picker("restriction[field_keys][]"), do: "field_keys"
  defp picker(_other), do: nil

  defp role_ids(params) do
    params["role_ids"] |> Enum.map(&Params.positive_integer/1) |> Enum.reject(&is_nil/1)
  end

  defp fields(params) do
    Enum.map(params["field_keys"], fn key ->
      [table_id, field_id] = String.split(key, @separator, parts: 2)
      {table_id, field_id}
    end)
  end

  # --- options and labels ----------------------------------------------------

  defp table_options(catalog), do: Enum.map(catalog, &{&1.label, &1.id})

  defp role_options(roles), do: Enum.map(roles, &{&1.name, Integer.to_string(&1.id)})

  # The fields of the chosen tables, in catalog order. With one table chosen
  # the field's own label is enough; with more, each option names its table
  # so "Email" of two tables cannot be confused.
  defp field_options(catalog, table_ids) do
    chosen = Enum.filter(catalog, &(&1.id in table_ids))

    for table <- chosen, field <- table.fields do
      label = if length(chosen) > 1, do: "#{table.label} › #{field.label}", else: field.label
      {label, table.id <> @separator <> field.id}
    end
  end

  defp chosen_labels(options, values) do
    for {label, value} <- options, value in values, do: label
  end

  defp chosen_field_labels(catalog, keys) do
    for table <- catalog, field <- table.fields, (table.id <> @separator <> field.id) in keys do
      "#{table.label} › #{field.label}"
    end
  end

  defp subject(restriction), do: "#{restriction.table_label} › #{restriction.field_label}"

  # One sentence, in the dialog, saying what saving will do, once there is
  # something to say: the roles named will not see the fields named.
  defp outcome_sentence([], _roles), do: nil
  defp outcome_sentence(_fields, []), do: nil

  defp outcome_sentence(fields, roles) do
    gettext("%{roles} will read %{fields} as Restricted. Every other role sees the value.",
      roles: join(roles),
      fields: join(fields)
    )
  end

  defp ready?(fields, roles), do: fields != [] and roles != []

  defp submit_label([]), do: gettext("Restrict fields")
  defp submit_label([_one]), do: gettext("Restrict field")
  defp submit_label(fields), do: gettext("Restrict %{count} fields", count: length(fields))

  defp saved_message([restriction]) do
    gettext("%{field} is restricted for %{roles}.",
      field: subject(restriction),
      roles: join(restriction.role_names)
    )
  end

  defp saved_message([first | _rest] = restrictions) do
    gettext("%{count} fields are restricted for %{roles}.",
      count: length(restrictions),
      roles: join(first.role_names)
    )
  end

  defp join([one]), do: one
  defp join([first, second]), do: "#{first} and #{second}"

  defp join(items) do
    {head, [last]} = Enum.split(items, -1)
    Enum.join(head, ", ") <> " and " <> last
  end
end
