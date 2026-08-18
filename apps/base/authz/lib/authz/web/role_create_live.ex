defmodule Bilimbi.Base.Authz.Web.RoleCreateLive do
  @moduledoc """
  Creates a custom role, owned by a company the operator chooses.

  Ports Belimbing's `app/Base/Authz/Livewire/Roles/Create.php`, where the owning
  company is a **required** `<select>` built from
  `Company::query()->forTenant($tenantId)->orderBy('name')`. This screen first
  shipped binding the company to the session instead (#264); that diverged for
  two accounts Belimbing supports -- a tenant administrator creating a role for
  a subsidiary, and an operator with no session company at all, for whom
  `create_role/3` could only ever answer `:company_not_found`.

  Options come from `Authz.companies_in_scope/1` rather than a Core query,
  because Base naming Core is the layering violation the directory seam exists
  to prevent.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.Authz
  alias Ecto.Changeset

  @field_types %{name: :string, code: :string, description: :string, company_id: :integer}

  @impl true
  def mount(_params, _session, socket) do
    companies = Authz.companies_in_scope(socket.assigns.current_scope.scope)
    company_ids = Enum.map(companies, & &1.id)

    {:ok,
     socket
     |> assign(:page_title, "Create Role")
     |> assign(:active_nav, "admin.authz.role")
     |> assign(:companies, companies)
     |> assign(:company_ids, company_ids)
     |> assign(:company_options, Enum.map(companies, &{&1.name, &1.id}))
     |> assign_form(form_changeset(default_params(socket, companies), company_ids))}
  end

  # Belimbing preselects nothing, but an operator whose session company is one
  # of the options should not have to pick it again. Only when it is genuinely
  # in scope -- defaulting to a company the directory did not list would offer a
  # value `create_role/3` then rejects.
  defp default_params(socket, companies) do
    session_company = socket.assigns.current_scope.user["company_id"]

    if Enum.any?(companies, &(&1.id == session_company)) do
      %{"company_id" => to_string(session_company)}
    else
      %{}
    end
  end

  @impl true
  def handle_event("validate", %{"role" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params, socket.assigns.company_ids))}
  end

  def handle_event("save", %{"role" => params}, socket) do
    changeset = form_changeset(params, socket.assigns.company_ids)

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
      {:ok, role} ->
        {:noreply, after_create(socket, role)}

      # Now that the operator picks the company, this is a correctable field
      # error rather than a broken session: the chosen company left scope
      # between page load and submit, or was never in it.
      {:error, :company_not_found} ->
        {:noreply,
         assign_form(
           socket,
           changeset
           |> add_error(:company_id, "is no longer available; choose another company")
           |> Map.put(:action, :validate)
         )}

      {:error, %Changeset{} = domain} ->
        {:noreply, assign_form(socket, copy_domain_errors(changeset, domain))}
    end
  end

  # A new custom role has no capabilities, so it does nothing until someone
  # opens it and grants some. `RoleShowLive` is where that happens, and it is
  # where Belimbing lands the operator (`Create.php:53`). Returning to the index
  # leaves a row that looks finished and is inert.
  #
  # Every destination is capability-gated, so the landing place has to be one
  # this actor may actually open -- `/authz/roles` needs `role.list`, not
  # `role.view` (`priv/web_routes.exs:6`). Navigating somewhere they will be
  # bounced off is the same dashboard-dump this change exists to avoid; it just
  # takes two redirects to get there instead of one.
  #
  # Belimbing redirects to Show unconditionally and 403s an actor holding
  # `role.create` without `role.view`. Deliberately not copied: the role is
  # created either way, so no business meaning changes.
  defp after_create(socket, role) do
    scope = socket.assigns.current_scope
    socket = put_flash(socket, :info, "Role created.")

    cond do
      allowed?(scope, "admin.authz.role.view") ->
        push_navigate(socket, to: ~p"/authz/roles/#{role.id}")

      allowed?(scope, "admin.authz.role.list") ->
        push_navigate(socket, to: ~p"/authz/roles")

      # Create is the one page this actor can hold. Stay, with a cleared form,
      # so the confirmation is visible and they can create another.
      true ->
        assign_form(socket, form_changeset(%{}, socket.assigns.company_ids))
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

  # Membership rather than a positivity check: Belimbing validates
  # `Rule::exists(Company::class, 'id')->where('tenant_id', $tenantId)`, which
  # is membership in the tenant's companies -- the same list the picker was
  # built from. It also rejects another tenant's id and a plausible id that
  # does not exist, which `greater_than: 0` would pass to the domain call.
  #
  # The wording differs from the domain error on purpose. "No longer available"
  # describes a company that was offered and then left scope; a company that
  # was never offered has not become unavailable, and saying so was the
  # misleading message this validation was added to remove.
  #
  # This does not replace the check in `create_role/3`: options are read at
  # mount, so a company can leave scope before submit, and that window is the
  # domain's to close.
  defp form_changeset(params, valid_company_ids) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:name, :code, :company_id])
    |> validate_inclusion(:company_id, valid_company_ids,
      message: "is not a company you can create roles for"
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
      <.page id="role-create-page" variant={:form}>
        <.header>
          Create Role
          <:subtitle>A custom role owned by a company in your tenant</:subtitle>
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
              id="role-company-scope"
              type="select"
              label="Company Scope"
              prompt="Select a company"
              options={@company_options}
              hint="The owning company keeps this custom role inside the current tenant."
            />
            <.input field={@form[:name]} type="text" label="Name" />
            <.input
              field={@form[:code]}
              type="text"
              label="Code"
              placeholder="billing_manager"
              hint="Lowercase letters, digits and underscores. Unique within the selected company."
            />
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
      </.page>
    </Layouts.app>
    """
  end
end
