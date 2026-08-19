defmodule Bilimbi.Core.Company.Web.LegalEntityTypesLive do
  @moduledoc """
  Administration for Legal Entity Types (e.g. LLC, Corporation, Sole Proprietorship).
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.LegalEntityType

  @create_capability "admin.company.create"
  @update_capability "admin.company.update"
  @delete_capability "admin.company.delete"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, types} = Company.list_legal_entity_types()

    {:ok,
     socket
     |> assign(:page_title, "Legal Entity Types")
     |> assign(:active_nav, "admin.company.legal-entity-type")
     |> assign(:can_create?, allowed?(socket.assigns.current_scope, @create_capability))
     |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
     |> assign(:can_delete?, allowed?(socket.assigns.current_scope, @delete_capability))
     |> assign(:types_count, length(types))
     |> assign(:modal_action, nil)
     |> assign(:editing_type, nil)
     |> assign_form(nil)
     |> stream(:types, types)}
  end

  @impl true
  def handle_event("new", _params, %{assigns: %{can_create?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("new", _params, socket) do
    changeset = LegalEntityType.changeset(%LegalEntityType{}, %{is_active: true})

    {:noreply,
     socket
     |> assign(:modal_action, :new)
     |> assign(:editing_type, %LegalEntityType{})
     |> assign_form(changeset)}
  end

  def handle_event("edit", _params, %{assigns: %{can_update?: false}} = socket),
    do: write_forbidden(socket)

  def handle_event("edit", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {type_id, ""} ->
        case Company.get_legal_entity_type(type_id) do
          {:ok, type} ->
            changeset = LegalEntityType.update_changeset(type, %{})

            {:noreply,
             socket
             |> assign(:modal_action, :edit)
             |> assign(:editing_type, type)
             |> assign_form(changeset)}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Legal entity type not found.")}
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

  def handle_event("validate", %{"legal_entity_type" => params}, socket) do
    changeset =
      case socket.assigns.modal_action do
        :edit ->
          socket.assigns.editing_type
          |> LegalEntityType.update_changeset(params)
          |> Map.put(:action, :validate)

        _ ->
          %LegalEntityType{}
          |> LegalEntityType.changeset(params)
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

  def handle_event("save", %{"legal_entity_type" => params}, socket) do
    case socket.assigns.modal_action do
      :new ->
        case Company.create_legal_entity_type(params) do
          {:ok, _created_type} ->
            {:ok, types} = Company.list_legal_entity_types()

            {:noreply,
             socket
             |> put_flash(:info, "Legal entity type created successfully.")
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

        case Company.update_legal_entity_type(type, params) do
          {:ok, updated_type} ->
            {:noreply,
             socket
             |> put_flash(:info, "Legal entity type updated successfully.")
             |> assign(:modal_action, nil)
             |> assign(:editing_type, nil)
             |> assign_form(nil)
             |> stream_insert(:types, updated_type)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Legal entity type not found.")
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
        case Company.toggle_legal_entity_type_active(type_id) do
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
        case Company.delete_legal_entity_type(type_id) do
          :ok ->
            {:ok, types} = Company.list_legal_entity_types()

            {:noreply,
             socket
             |> put_flash(:info, "Legal entity type deleted.")
             |> assign(:types_count, length(types))
             |> stream(:types, types, reset: true)}

          {:error, :in_use} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Cannot delete legal entity type because it is referenced by one or more companies."
             )}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Legal entity type not found.")}
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

  defp assign_form(socket, nil), do: assign(socket, :form, nil)

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "legal_entity_type"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="legal-entity-types-index">
        <.header>
          Legal Entity Types
          <:subtitle>Manage corporate and legal forms recognized in this platform</:subtitle>
          <:actions>
            <.button navigate={~p"/companies"} class="text-xs">
              Back to companies
            </.button>
            <.button
              :if={@can_create?}
              id="new-legal-entity-type-btn"
              phx-click="new"
              variant="primary"
              class="text-xs"
            >
              Add Legal Entity Type
            </.button>
          </:actions>
        </.header>

        <.card id="legal-entity-types-card" inner_class="p-0">
          <.table
            id="legal-entity-types"
            rows={@streams.types}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, type} -> type end}
            caption="Legal Entity Types"
            framed={false}
          >
            <:col :let={type} label="Code">
              <code class="text-xs font-medium">{type.code}</code>
            </:col>
            <:col :let={type} label="Name">
              <span class="font-medium text-ink-strong">{type.name}</span>
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
                  id={"toggle-type-#{type.id}"}
                  phx-click="toggle_active"
                  phx-value-id={type.id}
                  class="text-xs text-ink-subtle hover:text-ink hover:underline"
                >
                  {if type.is_active, do: "Deactivate", else: "Activate"}
                </button>
                <button
                  :if={@can_update?}
                  type="button"
                  id={"edit-type-#{type.id}"}
                  phx-click="edit"
                  phx-value-id={type.id}
                  class="text-xs text-action hover:underline"
                >
                  Edit
                </button>
                <button
                  :if={@can_delete?}
                  type="button"
                  id={"delete-type-#{type.id}"}
                  phx-click="delete"
                  phx-value-id={type.id}
                  data-confirm="Are you sure you want to delete this legal entity type?"
                  class="text-xs text-danger hover:underline"
                >
                  Delete
                </button>
              </div>
            </:action>
            <:empty :if={@types_count == 0}>
              No legal entity types defined yet.
            </:empty>
          </.table>
        </.card>

        <div
          :if={@modal_action in [:new, :edit]}
          id="legal-entity-type-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              {if @modal_action == :new,
                do: "New Legal Entity Type",
                else: "Edit Legal Entity Type"}
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              {if @modal_action == :new,
                do: "Create a new legal structure type for companies.",
                else: "Update legal entity type details."}
            </p>

            <.form
              :if={@form}
              for={@form}
              id="legal-entity-type-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-4 space-y-4"
            >
              <.input
                field={@form[:code]}
                id="legal-entity-type-code"
                label="Code"
                placeholder="e.g. LLC, CORP, PT"
                disabled={@modal_action == :edit}
                required
              />
              <.input
                field={@form[:name]}
                id="legal-entity-type-name"
                label="Name"
                placeholder="e.g. Limited Liability Company"
                required
              />
              <.input
                field={@form[:description]}
                id="legal-entity-type-description"
                type="textarea"
                label="Description"
                placeholder="Optional description of this legal entity type"
              />
              <.input
                :if={@modal_action == :new}
                field={@form[:is_active]}
                id="legal-entity-type-active"
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
