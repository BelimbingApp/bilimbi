defmodule Bilimbi.Core.Company.Web.ReferenceTypesLive do
  @moduledoc """
  Administration for one company reference type.

  Department types and legal entity types are the same modal table. The route
  picks a spec (`spec/1`): nouns, DOM ids, and whether the category filter is
  on. A new reference type is another spec, not a copied LiveView.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.Params
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.LegalEntityType

  @create_capability "admin.company.create"
  @update_capability "admin.company.update"
  @delete_capability "admin.company.delete"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:spec, nil)
     |> assign(:reference_path, nil)
     |> assign(:page_title, "Company types")
     |> assign(:active_nav, nil)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    path = URI.parse(uri).path

    if socket.assigns.reference_path == path do
      {:noreply, socket}
    else
      spec = spec(path)
      {:ok, types} = list_types(spec, "all")

      {:noreply,
       socket
       |> assign(:page_title, spec.page_title)
       |> assign(:active_nav, spec.active_nav)
       |> assign(:reference_path, path)
       |> assign(:spec, spec)
       |> assign(:can_create?, allowed?(socket.assigns.current_scope, @create_capability))
       |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
       |> assign(:can_delete?, allowed?(socket.assigns.current_scope, @delete_capability))
       |> assign(:types_count, length(types))
       |> assign(:selected_category, "all")
       |> assign(:modal_action, nil)
       |> assign(:editing_type, nil)
       |> assign(:pending_delete, nil)
       |> assign_form(nil)
       |> stream(:types, types, reset: true)}
    end
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    if socket.assigns.spec.category? do
      {:ok, types} = list_types(socket.assigns.spec, category)

      {:noreply,
       socket
       |> assign(:selected_category, category)
       |> assign(:types_count, length(types))
       |> stream(:types, types, reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new", _params, %{assigns: %{can_create?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("new", _params, socket) do
    if permit?(socket, @create_capability) do
      open_new(socket)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("edit", _params, %{assigns: %{can_update?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("edit", %{"id" => id}, socket) do
    if permit?(socket, @update_capability) do
      open_edit(socket, id)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_action, nil)
     |> assign(:editing_type, nil)
     |> assign_form(nil)}
  end

  def handle_event("validate", params, socket) do
    spec = socket.assigns.spec
    form_params = Map.get(params, spec.form_as, %{})

    changeset =
      case socket.assigns.modal_action do
        :edit ->
          socket.assigns.editing_type
          |> spec.schema.update_changeset(form_params)
          |> Map.put(:action, :validate)

        _ ->
          spec.schema
          |> struct()
          |> spec.schema.changeset(form_params)
          |> Map.put(:action, :validate)
      end

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event(
        "save",
        _params,
        %{assigns: %{modal_action: :edit, can_update?: false}} = socket
      ),
      do: write_forbidden(socket)

  def handle_event(
        "save",
        _params,
        %{assigns: %{modal_action: action, can_create?: false}} = socket
      )
      when action != :edit,
      do: write_forbidden(socket)

  def handle_event("save", params, socket) do
    spec = socket.assigns.spec
    form_params = Map.get(params, spec.form_as, %{})
    scope = socket.assigns.current_scope.scope

    case socket.assigns.modal_action do
      :new ->
        if permit?(socket, @create_capability) do
          create_type(socket, scope, form_params)
        else
          write_forbidden(socket)
        end

      :edit ->
        if permit?(socket, @update_capability) do
          update_type(socket, scope, form_params)
        else
          write_forbidden(socket)
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_active", _params, %{assigns: %{can_update?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("toggle_active", %{"id" => id}, socket) do
    if permit?(socket, @update_capability) do
      toggle_type(socket, id)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("request_delete", _params, %{assigns: %{can_delete?: false}} = socket),
    do: write_forbidden(socket)

  # Deleting confirms through the shared dialog: the request holds the type
  # whose consequence the dialog states, and `delete` acts on that held type
  # rather than on a client-supplied id, so what was confirmed is what runs.
  def handle_event("request_delete", %{"id" => id}, socket) do
    if permit?(socket, @delete_capability) do
      request_delete(socket, id)
    else
      write_forbidden(socket)
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("delete", _params, %{assigns: %{can_delete?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("delete", _params, %{assigns: %{pending_delete: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("delete", _params, %{assigns: %{pending_delete: type}} = socket) do
    if permit?(socket, @delete_capability) do
      delete_type(socket, type)
    else
      write_forbidden(assign(socket, :pending_delete, nil))
    end
  end

  defp open_new(socket) do
    spec = socket.assigns.spec
    changeset = spec.schema.changeset(struct(spec.schema), spec.new_attrs)

    {:noreply,
     socket
     |> clear_flash()
     |> assign(:modal_action, :new)
     |> assign(:editing_type, struct(spec.schema, spec.new_struct))
     |> assign_form(changeset)}
  end

  defp open_edit(socket, id) do
    spec = socket.assigns.spec

    with {:ok, type_id} <- Params.positive_id(id),
         {:ok, type} <- get_type(spec, type_id) do
      changeset = spec.schema.update_changeset(type, %{})

      {:noreply,
       socket
       |> clear_flash()
       |> assign(:modal_action, :edit)
       |> assign(:editing_type, type)
       |> assign_form(changeset)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, spec.not_found)}

      :error ->
        {:noreply, socket}
    end
  end

  defp create_type(socket, scope, params) do
    spec = socket.assigns.spec

    case create(spec, scope, params) do
      {:ok, _type} ->
        {:ok, types} = list_types(spec, socket.assigns.selected_category)

        {:noreply,
         socket
         |> put_flash(:success, spec.created)
         |> assign(:modal_action, nil)
         |> assign(:editing_type, nil)
         |> assign(:types_count, length(types))
         |> assign_form(nil)
         |> stream(:types, types, reset: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        write_forbidden(socket)
    end
  end

  defp update_type(socket, scope, params) do
    spec = socket.assigns.spec
    type = socket.assigns.editing_type

    case update(spec, scope, type, params) do
      {:ok, updated_type} ->
        {:noreply,
         socket
         |> put_flash(:success, spec.updated)
         |> assign(:modal_action, nil)
         |> assign(:editing_type, nil)
         |> assign_form(nil)
         |> stream_insert(:types, updated_type)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, spec.not_found)
         |> assign(:modal_action, nil)}

      {:error, :forbidden} ->
        write_forbidden(socket)
    end
  end

  defp toggle_type(socket, id) do
    spec = socket.assigns.spec

    with {:ok, type_id} <- Params.positive_id(id),
         {:ok, updated_type} <-
           toggle(spec, socket.assigns.current_scope.scope, type_id) do
      {:noreply,
       socket
       |> put_flash(:success, "Status updated successfully.")
       |> stream_insert(:types, updated_type)}
    else
      {:error, :forbidden} ->
        write_forbidden(socket)

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update status.")}

      :error ->
        {:noreply, socket}
    end
  end

  defp request_delete(socket, id) do
    spec = socket.assigns.spec

    with {:ok, type_id} <- Params.positive_id(id),
         {:ok, type} <- get_type(spec, type_id) do
      {:noreply, socket |> clear_flash() |> assign(:pending_delete, type)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, spec.not_found)}

      :error ->
        {:noreply, socket}
    end
  end

  defp delete_type(socket, type) do
    spec = socket.assigns.spec
    socket = assign(socket, :pending_delete, nil)

    case delete(spec, socket.assigns.current_scope.scope, type.id) do
      :ok ->
        {:ok, types} = list_types(spec, socket.assigns.selected_category)

        {:noreply,
         socket
         |> put_flash(:success, spec.deleted)
         |> assign(:types_count, length(types))
         |> stream(:types, types, reset: true)}

      {:error, :in_use} ->
        {:noreply, put_flash(socket, :error, spec.in_use.(type))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, spec.not_found)}

      {:error, :forbidden} ->
        write_forbidden(socket)
    end
  end

  # `can_*?` assigns only decide which controls render. A LiveView outlives
  # its mount, so every write asks Authz again with the sealed scope.
  defp permit?(socket, capability) do
    Authz.can(socket.assigns.current_scope.scope, capability).allowed
  end

  defp write_forbidden(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "You do not have permission to change company administration data."
     )}
  end

  defp assign_form(socket, nil), do: assign(socket, :form, nil)

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: socket.assigns.spec.form_as))
  end

  defp list_types(%{kind: :department_type}, "all"), do: Company.list_department_types()

  defp list_types(%{kind: :department_type}, category),
    do: Company.list_department_types(category: category)

  defp list_types(%{kind: :legal_entity_type}, _category), do: Company.list_legal_entity_types()

  defp get_type(%{kind: :department_type}, id), do: Company.get_department_type(id)
  defp get_type(%{kind: :legal_entity_type}, id), do: Company.get_legal_entity_type(id)

  defp create(%{kind: :department_type}, scope, attrs),
    do: Company.create_department_type(scope, attrs)

  defp create(%{kind: :legal_entity_type}, scope, attrs),
    do: Company.create_legal_entity_type(scope, attrs)

  defp update(%{kind: :department_type}, scope, type, attrs),
    do: Company.update_department_type(scope, type, attrs)

  defp update(%{kind: :legal_entity_type}, scope, type, attrs),
    do: Company.update_legal_entity_type(scope, type, attrs)

  defp toggle(%{kind: :department_type}, scope, id),
    do: Company.toggle_department_type_active(scope, id)

  defp toggle(%{kind: :legal_entity_type}, scope, id),
    do: Company.toggle_legal_entity_type_active(scope, id)

  defp delete(%{kind: :department_type}, scope, id),
    do: Company.delete_department_type(scope, id)

  defp delete(%{kind: :legal_entity_type}, scope, id),
    do: Company.delete_legal_entity_type(scope, id)

  defp category_options do
    Enum.map(DepartmentType.categories(), fn cat ->
      {String.capitalize(cat), cat}
    end)
  end

  defp spec("/companies/department-types") do
    %{
      kind: :department_type,
      schema: DepartmentType,
      category?: true,
      form_as: "department_type",
      page_title: "Department Types",
      subtitle: "Manage standard department categories and organizational functions",
      active_nav: "admin.company.department-type",
      add_label: "Department Type",
      caption: "Department Types",
      empty: "No department types found.",
      new_title: "New Department Type",
      edit_title: "Edit Department Type",
      new_description: "Create a new department type definition.",
      edit_description: "Update department type details.",
      code_placeholder: "e.g. ENG, HR, FIN",
      name_placeholder: "e.g. Engineering",
      description_placeholder: "Optional description of this department type",
      not_found: "Department type not found.",
      created: "Department type created successfully.",
      updated: "Department type updated successfully.",
      deleted: "Department type deleted.",
      confirm_noun: "Department type",
      confirm_detail: "It can no longer be chosen for a department. This cannot be undone.",
      new_attrs: %{category: "operational", is_active: true},
      new_struct: %{category: "operational"},
      in_use: fn type ->
        "#{type.name} was not deleted: one or more company departments still use it. " <>
          "Change those departments' type first."
      end,
      dom: %{
        page: "department-types-index",
        back: "department-types-back",
        new: "new-department-type-btn",
        card: "department-types-card",
        table: "department-types",
        toggle: "toggle-dept-type",
        edit: "edit-dept-type",
        delete: "delete-dept-type",
        modal: "department-type-modal",
        form: "department-type-form",
        field: "department-type",
        confirm: "delete-dept-type-confirm"
      }
    }
  end

  defp spec("/companies/legal-entity-types") do
    %{
      kind: :legal_entity_type,
      schema: LegalEntityType,
      category?: false,
      form_as: "legal_entity_type",
      page_title: "Legal Entity Types",
      subtitle: "Manage corporate and legal forms recognized in this platform",
      active_nav: "admin.company.legal-entity-type",
      add_label: "Legal Entity Type",
      caption: "Legal Entity Types",
      empty: "No legal entity types defined yet.",
      new_title: "New Legal Entity Type",
      edit_title: "Edit Legal Entity Type",
      new_description: "Create a new legal structure type for companies.",
      edit_description: "Update legal entity type details.",
      code_placeholder: "e.g. LLC, CORP, PT",
      name_placeholder: "e.g. Limited Liability Company",
      description_placeholder: "Optional description of this legal entity type",
      not_found: "Legal entity type not found.",
      created: "Legal entity type created successfully.",
      updated: "Legal entity type updated successfully.",
      deleted: "Legal entity type deleted.",
      confirm_noun: "Legal entity type",
      confirm_detail: "It can no longer be chosen for a company. This cannot be undone.",
      new_attrs: %{is_active: true},
      new_struct: %{},
      in_use: fn type ->
        "#{type.name} was not deleted: one or more companies still use it. " <>
          "Change those companies' legal entity type first."
      end,
      dom: %{
        page: "legal-entity-types-index",
        back: "legal-entity-types-back",
        new: "new-legal-entity-type-btn",
        card: "legal-entity-types-card",
        table: "legal-entity-types",
        toggle: "toggle-type",
        edit: "edit-type",
        delete: "delete-type",
        modal: "legal-entity-type-modal",
        form: "legal-entity-type-form",
        field: "legal-entity-type",
        confirm: "delete-type-confirm"
      }
    }
  end

  @impl true
  def render(assigns) do
    assigns =
      if assigns.spec && assigns.spec.category? do
        assign(assigns, :category_options, category_options())
      else
        assigns
      end

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page :if={@spec} id={@spec.dom.page}>
        <.header>
          {@spec.page_title}
          <:subtitle>{@spec.subtitle}</:subtitle>
          <:actions>
            <.back_link id={@spec.dom.back} navigate={~p"/companies"} title="Back to companies" />
            <.create_button
              :if={@can_create?}
              id={@spec.dom.new}
              noun={@spec.add_label}
              phx-click="new"
              class="text-xs"
            />
          </:actions>
        </.header>

        <div :if={@spec.category?} class="mb-4 flex flex-wrap items-center gap-2">
          <span class="w-full text-xs font-semibold text-ink-subtle sm:w-auto">Category:</span>
          <.button
            phx-click="filter_category"
            phx-value-category="all"
            variant={if @selected_category == "all", do: "primary", else: nil}
            class="text-xs py-1 px-2.5"
          >
            All
          </.button>
          <.button
            :for={cat <- DepartmentType.categories()}
            phx-click="filter_category"
            phx-value-category={cat}
            variant={if @selected_category == cat, do: "primary", else: nil}
            class="text-xs py-1 px-2.5"
          >
            {String.capitalize(cat)}
          </.button>
        </div>

        <.card id={@spec.dom.card} inner_class="p-0">
          <.table
            id={@spec.dom.table}
            rows={@streams.types}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, type} -> type end}
            caption={@spec.caption}
            framed={false}
          >
            <:col :let={type} label="Code">
              <code class="text-xs font-medium">{type.code}</code>
            </:col>
            <:col :let={type} label="Name">
              <span class="font-medium text-ink-strong">{type.name}</span>
            </:col>
            <:col :let={type} :if={@spec.category?} label="Category">
              <.badge kind={:neutral} dot={false}>
                {String.capitalize(type.category)}
              </.badge>
            </:col>
            <:col :let={type} label="Description">
              <span class="text-xs text-ink-subtle">{type.description || "—"}</span>
            </:col>
            <:col :let={type} label="Status">
              <.badge kind={if type.is_active, do: :success, else: :neutral}>
                {if type.is_active, do: "active", else: "inactive"}
              </.badge>
            </:col>
            <:action :let={type}>
              <div class="flex items-center gap-2">
                <button
                  :if={@can_update?}
                  type="button"
                  id={"#{@spec.dom.toggle}-#{type.id}"}
                  phx-click="toggle_active"
                  phx-value-id={type.id}
                  class="text-xs text-ink-subtle hover:text-ink hover:underline"
                >
                  {if type.is_active, do: "Deactivate", else: "Activate"}
                </button>
                <.icon_button
                  :if={@can_update?}
                  icon="edit"
                  label={"Edit #{type.name}"}
                  id={"#{@spec.dom.edit}-#{type.id}"}
                  phx-click="edit"
                  phx-value-id={type.id}
                />
                <.icon_button
                  :if={@can_delete?}
                  icon="delete"
                  label={"Delete #{type.name}"}
                  kind={:danger}
                  id={"#{@spec.dom.delete}-#{type.id}"}
                  phx-click="request_delete"
                  phx-value-id={type.id}
                />
              </div>
            </:action>
            <:empty :if={@types_count == 0}>
              {@spec.empty}
            </:empty>
          </.table>
        </.card>

        <.modal
          :if={@modal_action in [:new, :edit]}
          id={@spec.dom.modal}
          title={if @modal_action == :new, do: @spec.new_title, else: @spec.edit_title}
          flash={@flash}
          on_cancel={JS.push("close_modal")}
        >
          <:description>
            {if @modal_action == :new, do: @spec.new_description, else: @spec.edit_description}
          </:description>

          <.form
            :if={@form}
            for={@form}
            id={@spec.dom.form}
            phx-change="validate"
            phx-submit="save"
            class="mt-4 space-y-4"
          >
            <.input
              field={@form[:code]}
              id={"#{@spec.dom.field}-code"}
              label="Code"
              placeholder={@spec.code_placeholder}
              disabled={@modal_action == :edit}
              required
            />
            <.input
              field={@form[:name]}
              id={"#{@spec.dom.field}-name"}
              label="Name"
              placeholder={@spec.name_placeholder}
              required
            />
            <.input
              :if={@spec.category?}
              field={@form[:category]}
              id={"#{@spec.dom.field}-category"}
              type="select"
              label="Category"
              options={@category_options}
              required
            />
            <.input
              field={@form[:description]}
              id={"#{@spec.dom.field}-description"}
              type="textarea"
              label="Description"
              placeholder={@spec.description_placeholder}
            />
            <.input
              :if={@modal_action == :new}
              field={@form[:is_active]}
              id={"#{@spec.dom.field}-active"}
              type="checkbox"
              label="Active"
            />

            <div class="mt-6 flex justify-end gap-2">
              <.button type="button" phx-click="close_modal">
                Cancel
              </.button>
              <.button type="submit" variant="primary">
                Save
              </.button>
            </div>
          </.form>
        </.modal>

        <.confirm_dialog
          :if={@pending_delete}
          id={@spec.dom.confirm}
          consequence={"#{@spec.confirm_noun} “#{@pending_delete.name}” will be deleted."}
          detail={@spec.confirm_detail}
          confirm="Delete"
          working="Deleting…"
          on_confirm={JS.push("delete")}
          on_cancel={JS.push("cancel_delete")}
        />
      </.page>
    </Layouts.app>
    """
  end
end
