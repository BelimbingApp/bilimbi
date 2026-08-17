defmodule Bilimbi.Base.Authz.Web.RoleCreateLive do
  @moduledoc false

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.Authz
  alias Ecto.Changeset

  @field_types %{name: :string, code: :string, description: :string}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create Role")
     |> assign(:active_nav, "admin.authz.role")
     |> assign_form(form_changeset(%{}))}
  end

  @impl true
  def handle_event("validate", %{"role" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params))}
  end

  def handle_event("save", %{"role" => params}, socket) do
    changeset = form_changeset(params)

    if changeset.valid? do
      save(socket, changeset)
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, changeset) do
    scope = socket.assigns.current_scope.scope
    company_id = socket.assigns.current_scope.user["company_id"]

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

      # The company comes from the session, so this is a signed-in account whose
      # company left scope mid-session -- not something the form can correct.
      {:error, :company_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your company is no longer in scope; sign in again.")
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

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:name, :code])
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
          <:subtitle>A custom role owned by your company</:subtitle>
          <:actions>
            <.button id="role-back" navigate={~p"/authz/roles"}>
              Back to roles
            </.button>
          </:actions>
        </.header>

        <.form for={@form} id="role-form" phx-change="validate" phx-submit="save" class="space-y-5">
          <section class="rounded-xl border border-line bg-surface px-6 py-5">
            <.input field={@form[:name]} type="text" label="Name" />
            <.input
              field={@form[:code]}
              type="text"
              label="Code"
              placeholder="billing_manager"
            />
            <p class="mt-1 text-xs text-ink-subtle">
              Lowercase letters, digits and underscores. Unique within your company.
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
