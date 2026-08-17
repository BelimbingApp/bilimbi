defmodule Bilimbi.Base.Authz.Web.RoleCreateLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.Authz
  alias Ecto.Changeset

  @field_types %{name: :string, code: :string, description: :string, company_id: :integer}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    companies = Authz.companies_in_scope(scope)
    session_company_id = socket.assigns.current_scope.user["company_id"]

    {:ok,
     socket
     |> assign(:page_title, "Create Role")
     |> assign(:active_nav, "admin.authz.role")
     |> assign(:companies, companies)
     |> assign_form(form_changeset(%{"company_id" => session_company_id}, companies))}
  end

  @impl true
  def handle_event("validate", %{"role" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params, socket.assigns.companies))}
  end

  def handle_event("save", %{"role" => params}, socket) do
    changeset = form_changeset(params, socket.assigns.companies)

    if changeset.valid? do
      save(socket, changeset)
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, changeset) do
    scope = socket.assigns.current_scope.scope
    company_id = get_field(changeset, :company_id)

    attributes = %{
      name: get_field(changeset, :name),
      code: get_field(changeset, :code),
      description: get_field(changeset, :description)
    }

    case Authz.create_role(scope, company_id, attributes) do
      {:ok, _role} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role created.")
         |> push_navigate(to: ~p"/authz/roles")}

      # The picker is validated against `companies_in_scope/1`, so reaching this
      # means the company left the tenant between mount and submit.
      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "The selected company is no longer in this tenant.")
         |> assign_form(changeset)}

      {:error, %Changeset{} = domain} ->
        {:noreply, assign_form(socket, copy_domain_errors(changeset, domain))}
    end
  end

  # The database owns uniqueness of (company_id, code); the form cannot know it
  # without racing. Domain errors are copied back onto the form changeset so the
  # message lands on the field the user can actually edit.
  defp copy_domain_errors(form_changeset, %Changeset{} = domain) do
    Enum.reduce(domain.errors, form_changeset, fn {field, {message, opts}}, acc ->
      if Map.has_key?(@field_types, field) do
        add_error(acc, field, message, opts)
      else
        add_error(acc, :code, message, opts)
      end
    end)
    |> Map.put(:action, :validate)
  end

  defp form_changeset(params, companies) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:name, :code, :company_id])
    # The domain guard in create_role/3 still fails closed; this only decides
    # whether a bad selection is a field error or a flash.
    |> validate_inclusion(:company_id, Enum.map(companies, & &1.id),
      message: "is not a company in this tenant"
    )
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 255)
    |> validate_length(:description, max: 1_000)
    |> validate_format(:code, ~r/^[a-z0-9_]+$/,
      message: "may use only lowercase letters, digits and underscores"
    )
    |> Map.put(:action, :validate)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :role))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <div id="role-create-page" class="mx-auto max-w-2xl">
        <.header>
          Create Role
          <:subtitle>A custom role owned by a company in this tenant</:subtitle>
          <:actions>
            <.button id="role-back" navigate={~p"/authz/roles"}>
              Back to roles
            </.button>
          </:actions>
        </.header>

        <.form for={@form} id="role-form" phx-change="validate" phx-submit="save" class="space-y-5">
          <section class="rounded-xl border border-line bg-surface px-6 py-5">
            <.input
              field={@form[:company_id]}
              type="select"
              label="Company Scope"
              options={for company <- @companies, do: {company.name, company.id}}
              prompt={if @companies == [], do: "No companies in this tenant", else: nil}
            />
            <p class="mt-1 text-xs text-ink-subtle">
              The owning company keeps this custom role inside the current tenant.
            </p>
            <.input field={@form[:name]} type="text" label="Name" />
            <.input
              field={@form[:code]}
              type="text"
              label="Code"
              placeholder="billing_manager"
            />
            <p class="mt-1 text-xs text-ink-subtle">
              Lowercase letters, digits and underscores. Unique within the owning company.
            </p>
            <.input field={@form[:description]} type="textarea" label="Description" />
          </section>

          <div class="flex items-center justify-end gap-3">
            <.link id="role-cancel" navigate={~p"/authz/roles"} class="text-sm font-medium text-ink-muted hover:text-ink">
              Cancel
            </.link>
            <.button id="role-save" type="submit" variant="primary" phx-disable-with="Creating...">
              Create Role
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
