defmodule Bilimbi.Core.Company.Web.DepartmentTypesLive do
  @moduledoc """
  Administration for Department Types (e.g. Engineering, Sales, HR, Finance).
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.DepartmentType

  @create_capability "admin.company.create"
  @update_capability "admin.company.update"
  @delete_capability "admin.company.delete"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, types} = Company.list_department_types()

    {:ok,
     socket
     |> assign(:page_title, "Department Types")
     |> assign(:active_nav, "admin.company")
     |> assign(:can_create?, allowed?(socket.assigns.current_scope, @create_capability))
     |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
     |> assign(:can_delete?, allowed?(socket.assigns.current_scope, @delete_capability))
     |> assign(:types_count, length(types))
     |> assign(:selected_category, "all")
     |> assign(:modal_action, nil)
     |> assign(:editing_type, nil)
     |> assign_form(nil)
     |> stream(:types, types)}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    opts =
      if category == "all" do
        []
      else
        [category: category]
      end

    {:ok, types} = Company.list_department_types(opts)

    {:noreply,
     socket
     |> assign(:selected_category, category)
     |> assign(:types_count, length(types))
     |> stream(:types, types, reset: true)}
  end

  def handle_event("new", _params, %{assigns: %{can_create?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("new", _params, socket) do
    changeset =
      DepartmentType.changeset(%DepartmentType{}, %{
        category: "operational",
        is_active: true
      })

    {:noreply,
     socket
     |> assign(:modal_action, :new)
     |> assign(:editing_type, %DepartmentType{category: "operational"})
     |> assign_form(changeset)}
  end

  def handle_event("edit", _params, %{assigns: %{can_update?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("edit", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {type_id, ""} ->
        case Company.get_department_type(type_id) do
          {:ok, type} ->
            changeset = DepartmentType.update_changeset(type, %{})

            {:noreply,
             socket
             |> assign(:modal_action, :edit)
             |> assign(:editing_type, type)
             |> assign_form(changeset)}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Department type not found.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_action, nil)
     |> assign(:editing_type, nil)
     |> assign_form(nil)}
  end

  def handle_event("validate", %{"department_type" => params}, socket) do
    changeset =
      case socket.assigns.modal_action do
        :edit ->
          socket.assigns.editing_type
          |> DepartmentType.update_changeset(params)
          |> Map.put(:action, :validate)

        _ ->
          %DepartmentType{}
          |> DepartmentType.changeset(params)
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

  def handle_event("save", %{"department_type" => params}, socket) do
    case socket.assigns.modal_action do
      :new ->
        case Company.create_department_type(params) do
          {:ok, _type} ->
            {:ok, types} = reload_types(socket.assigns.selected_category)

            {:noreply,
             socket
             |> put_flash(:info, "Department type created successfully.")
             |> assign(:modal_action, nil)
             |> assign(:editing_type, nil)
             |> assign(:types_count, length(types))
             |> assign_form(nil)
             |> stream(:types, types, reset: true)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      :edit ->
        type = socket.assigns.editing_type

        case Company.update_department_type(type, params) do
          {:ok, updated_type} ->
            {:noreply,
             socket
             |> put_flash(:info, "Department type updated successfully.")
             |> assign(:modal_action, nil)
             |> assign(:editing_type, nil)
             |> assign_form(nil)
             |> stream_insert(:types, updated_type)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Department type not found.")
             |> assign(:modal_action, nil)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_active", _params, %{assigns: %{can_update?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("toggle_active", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {type_id, ""} ->
        case Company.toggle_department_type_active(type_id) do
          {:ok, updated_type} ->
            {:noreply,
             socket
             |> put_flash(:info, "Status updated successfully.")
             |> stream_insert(:types, updated_type)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not update status.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", _params, %{assigns: %{can_delete?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("delete", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {type_id, ""} ->
        case Company.delete_department_type(type_id) do
          :ok ->
            {:ok, types} = reload_types(socket.assigns.selected_category)

            {:noreply,
             socket
             |> put_flash(:info, "Department type deleted.")
             |> assign(:types_count, length(types))
             |> stream(:types, types, reset: true)}

          {:error, :in_use} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Cannot delete department type because it is referenced by one or more company departments."
             )}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Department type not found.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp write_forbidden(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "You do not have permission to change company administration data."
     )}
  end

  defp reload_types(category) do
    opts = if category == "all", do: [], else: [category: category]
    Company.list_department_types(opts)
  end

  defp assign_form(socket, nil), do: assign(socket, :form, nil)

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "department_type"))
  end

  defp category_options do
    Enum.map(DepartmentType.categories(), fn cat ->
      {String.capitalize(cat), cat}
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :category_options, category_options())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="department-types-index">
        <.header>
          Department Types
          <:subtitle>Manage standard department categories and organizational functions</:subtitle>
          <:actions>
            <.button navigate={~p"/companies"} class="text-xs">
              Back to companies
            </.button>
            <.button
              :if={@can_create?}
              id="new-department-type-btn"
              phx-click="new"
              variant="primary"
              class="text-xs"
            >
              Add Department Type
            </.button>
          </:actions>
        </.header>

        <div class="mb-4 flex items-center gap-2">
          <span class="text-xs font-semibold text-ink-subtle">Category:</span>
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

        <.card id="department-types-card" inner_class="p-0">
          <.table
            id="department-types"
            rows={@streams.types}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, type} -> type end}
            caption="Department Types"
            framed={false}
          >
            <:col :let={type} label="Code">
              <code class="text-xs font-medium">{type.code}</code>
            </:col>
            <:col :let={type} label="Name">
              <span class="font-medium text-ink-strong">{type.name}</span>
            </:col>
            <:col :let={type} label="Category">
              <.badge kind={:neutral}>
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
                  id={"toggle-dept-type-#{type.id}"}
                  phx-click="toggle_active"
                  phx-value-id={type.id}
                  class="text-xs text-ink-subtle hover:text-ink hover:underline"
                >
                  {if type.is_active, do: "Deactivate", else: "Activate"}
                </button>
                <button
                  :if={@can_update?}
                  type="button"
                  id={"edit-dept-type-#{type.id}"}
                  phx-click="edit"
                  phx-value-id={type.id}
                  class="text-xs text-action hover:underline"
                >
                  Edit
                </button>
                <button
                  :if={@can_delete?}
                  type="button"
                  id={"delete-dept-type-#{type.id}"}
                  phx-click="delete"
                  phx-value-id={type.id}
                  data-confirm="Are you sure you want to delete this department type?"
                  class="text-xs text-danger hover:underline"
                >
                  Delete
                </button>
              </div>
            </:action>
            <:empty :if={@types_count == 0}>
              No department types found.
            </:empty>
          </.table>
        </.card>

        <div
          :if={@modal_action in [:new, :edit]}
          id="department-type-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              {if @modal_action == :new,
                do: "New Department Type",
                else: "Edit Department Type"}
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              {if @modal_action == :new,
                do: "Create a new department type definition.",
                else: "Update department type details."}
            </p>

            <.form
              :if={@form}
              for={@form}
              id="department-type-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-4 space-y-4"
            >
              <.input
                field={@form[:code]}
                id="department-type-code"
                label="Code"
                placeholder="e.g. ENG, HR, FIN"
                disabled={@modal_action == :edit}
                required
              />
              <.input
                field={@form[:name]}
                id="department-type-name"
                label="Name"
                placeholder="e.g. Engineering"
                required
              />
              <.input
                field={@form[:category]}
                id="department-type-category"
                type="select"
                label="Category"
                options={@category_options}
                required
              />
              <.input
                field={@form[:description]}
                id="department-type-description"
                type="textarea"
                label="Description"
                placeholder="Optional description of this department type"
              />
              <.input
                :if={@modal_action == :new}
                field={@form[:is_active]}
                id="department-type-active"
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
          </div>
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
