defmodule Bilimbi.Core.Company.Web.RelationshipsLive do
  @moduledoc """
  Administration for inter-company relationships (parent/subsidiary, client/vendor, partner, etc.).
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Relationship

  @update_capability "admin.company.update"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope.scope

    case Integer.parse(id) do
      {company_id, ""} ->
        case Company.get_company(scope, company_id) do
          {:ok, company} ->
            {:ok, relationships} = Company.list_relationships(scope, company_id)

            {:ok,
             socket
             |> assign(:page_title, "#{Company.Summary.display_name(company)} — Relationships")
             |> assign(:active_nav, "admin.company")
             |> assign(:can_update?, allowed?(socket.assigns.current_scope, @update_capability))
             |> assign(:company, company)
             |> assign(:relationships_count, length(relationships))
             |> assign(:modal_action, nil)
             |> assign(:editing_rel, nil)
             |> assign(:available_companies, [])
             |> assign(:available_types, [])
             |> assign_form(nil)
             |> stream(:relationships, relationships)}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Company not found.")
             |> push_navigate(to: ~p"/companies")}
        end

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid company ID.")
         |> push_navigate(to: ~p"/companies")}
    end
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{can_update?: false}} = socket)
      when event in ["new", "edit", "save", "delete"],
      do: write_forbidden(socket)

  def handle_event("new", _params, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    with {:ok, companies} <- Company.list_available_related_companies(scope, company_id),
         {:ok, types} <- Company.list_active_relationship_types() do
      changeset =
        Relationship.changeset(%Relationship{company_id: company_id}, %{
          effective_from: Date.utc_today()
        })

      {:noreply,
       socket
       |> assign(:modal_action, :new)
       |> assign(:editing_rel, nil)
       |> assign(:available_companies, companies)
       |> assign(:available_types, types)
       |> assign_form(changeset)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not load related entities.")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Integer.parse(id) do
      {rel_id, ""} ->
        case Company.list_relationships(scope, company_id) do
          {:ok, relationships} ->
            case Enum.find(relationships, fn item -> item.id == rel_id end) do
              nil ->
                {:noreply, put_flash(socket, :error, "Relationship not found.")}

              item ->
                changeset = Relationship.update_changeset(item.relationship, %{})

                {:noreply,
                 socket
                 |> assign(:modal_action, :edit)
                 |> assign(:editing_rel, item)
                 |> assign_form(changeset)}
            end

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_action, nil)
     |> assign(:editing_rel, nil)
     |> assign_form(nil)}
  end

  def handle_event("validate", %{"relationship" => params}, socket) do
    changeset =
      case socket.assigns.modal_action do
        :edit ->
          socket.assigns.editing_rel.relationship
          |> Relationship.update_changeset(params)
          |> Map.put(:action, :validate)

        _ ->
          %Relationship{company_id: socket.assigns.company.id}
          |> Relationship.changeset(params)
          |> Map.put(:action, :validate)
      end

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"relationship" => params}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case socket.assigns.modal_action do
      :new ->
        case Company.create_relationship(scope, company_id, params) do
          {:ok, _rel} ->
            {:ok, relationships} = Company.list_relationships(scope, company_id)

            {:noreply,
             socket
             |> put_flash(:info, "Relationship established successfully.")
             |> assign(:modal_action, nil)
             |> assign(:relationships_count, length(relationships))
             |> assign_form(nil)
             |> stream(:relationships, relationships, reset: true)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not create relationship.")}
        end

      :edit ->
        rel_id = socket.assigns.editing_rel.id

        case Company.update_relationship(scope, company_id, rel_id, params) do
          {:ok, _rel} ->
            {:ok, relationships} = Company.list_relationships(scope, company_id)

            {:noreply,
             socket
             |> put_flash(:info, "Relationship updated successfully.")
             |> assign(:modal_action, nil)
             |> assign(:editing_rel, nil)
             |> assign_form(nil)
             |> stream(:relationships, relationships, reset: true)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not update relationship.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.company.id

    case Integer.parse(id) do
      {rel_id, ""} ->
        case Company.delete_relationship(scope, company_id, rel_id) do
          :ok ->
            {:ok, relationships} = Company.list_relationships(scope, company_id)

            {:noreply,
             socket
             |> put_flash(:info, "Relationship removed.")
             |> assign(:relationships_count, length(relationships))
             |> stream(:relationships, relationships, reset: true)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not remove relationship.")}
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
    assign(socket, :form, to_form(changeset, as: "relationship"))
  end

  defp company_options(companies) do
    Enum.map(companies, fn c ->
      {"#{c.name} (#{c.code})", c.id}
    end)
  end

  defp type_options(types) do
    Enum.map(types, fn t ->
      {t.name, t.id}
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:company_options, company_options(assigns.available_companies))
      |> assign(:type_options, type_options(assigns.available_types))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail}>
        <.header>
          {Company.Summary.display_name(@company)} — Relationships
          <:subtitle>
            <code class="text-xs font-medium">{@company.code}</code>
          </:subtitle>
          <:actions>
            <.button navigate={~p"/companies/#{@company.id}"} class="text-xs">
              Back to {Company.Summary.display_name(@company)}
            </.button>
            <.button
              :if={@can_update?}
              id="add-rel-btn"
              phx-click="new"
              variant="primary"
              class="text-xs"
            >
              Add Relationship
            </.button>
          </:actions>
        </.header>

        <.card id="company-relationships-card" inner_class="p-0">
          <.table
            id="company-relationships"
            rows={@streams.relationships}
            row_id={fn {id, _} -> id end}
            row_item={fn {_, item} -> item end}
            caption="Company Relationships"
            framed={false}
          >
            <:col :let={item} label="Related Company">
              <span class="font-medium text-ink-strong">{item.other_company.name}</span>
              <code class="block text-xs text-ink-subtle">{item.other_company.code}</code>
            </:col>
            <:col :let={item} label="Direction">
              <.badge kind={if item.direction == :outgoing, do: :info, else: :neutral}>
                {if item.direction == :outgoing, do: "Outgoing", else: "Incoming"}
              </.badge>
            </:col>
            <:col :let={item} label="Type">
              <span class="font-medium">{item.type.name}</span>
            </:col>
            <:col :let={item} label="Effective Period">
              <span class="text-xs text-ink-subtle">
                {item.effective_from || "Always"}
                {" → "}
                {item.effective_to || "Present"}
              </span>
            </:col>
            <:col :let={item} label="Status">
              <.badge kind={if item.is_active, do: :success, else: :neutral}>
                {if item.is_active, do: "active", else: "inactive"}
              </.badge>
            </:col>
            <:action :let={item}>
              <div class="flex items-center gap-2">
                <.icon_button
                  :if={@can_update?}
                  icon="hero-pencil"
                  label="Edit relationship dates"
                  id={"edit-rel-#{item.id}"}
                  phx-click="edit"
                  phx-value-id={item.id}
                />
                <.icon_button
                  :if={@can_update?}
                  icon="hero-link-slash"
                  label="Remove relationship"
                  kind={:danger}
                  id={"delete-rel-#{item.id}"}
                  phx-click="delete"
                  phx-value-id={item.id}
                  data-confirm="Are you sure you want to remove this relationship?"
                />
              </div>
            </:action>
            <:empty :if={@relationships_count == 0}>
              No company relationships configured yet.
            </:empty>
          </.table>
        </.card>

        <div
          :if={@modal_action in [:new, :edit]}
          id="relationship-modal"
          class="fixed inset-0 z-40 flex items-start justify-center bg-ink/40 p-6"
        >
          <div class="mt-16 w-full max-w-lg rounded-xl border border-line bg-surface p-6 shadow-sm">
            <h2 class="text-lg font-medium tracking-tight text-ink-strong">
              {if @modal_action == :new,
                do: "Add Relationship",
                else: "Edit Relationship Dates"}
            </h2>
            <p class="mt-1 text-xs text-ink-subtle">
              {if @modal_action == :new,
                do: "Establish a corporate relationship between #{Company.Summary.display_name(@company)} and another company.",
                else: "Update effective date range for relationship with #{@editing_rel.other_company.name}."}
            </p>

            <.form
              :if={@form}
              for={@form}
              id="relationship-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-4 space-y-4"
            >
              <.input
                :if={@modal_action == :new}
                field={@form[:related_company_id]}
                id="relationship-related-company-id"
                type="select"
                label="Related Company"
                options={@company_options}
                prompt="Select a company"
                required
              />
              <.input
                :if={@modal_action == :new}
                field={@form[:relationship_type_id]}
                id="relationship-type-id"
                type="select"
                label="Relationship Type"
                options={@type_options}
                prompt="Select relationship type"
                required
              />
              <.input
                field={@form[:effective_from]}
                id="relationship-effective-from"
                type="date"
                label="Effective From"
              />
              <.input
                field={@form[:effective_to]}
                id="relationship-effective-to"
                type="date"
                label="Effective To"
              />

              <div class="mt-6 flex justify-end gap-2">
                <.button type="button" phx-click="close_modal">
                  Cancel
                </.button>
                <.button
                  type="submit"
                  variant="primary"
                  disabled={@modal_action == :new and (@company_options == [] or @type_options == [])}
                >
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
