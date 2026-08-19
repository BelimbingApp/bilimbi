defmodule Bilimbi.Core.Company.Web.PlatformOperatorSetupLive do
  @moduledoc """
  Designate or create the platform-operator primary company.

  Ports Belimbing `app/Core/Company/Livewire/Setup/PlatformOperator.php`.
  The Mix task `bilimbi.platform.provision` remains the CLI path; this screen
  is the authenticated operator UI. Numeric tenant or company IDs have no
  special meaning.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Ecto.Changeset

  @field_types %{
    name: :string,
    legal_name: :string,
    registration_number: :string,
    tax_id: :string,
    jurisdiction: :string,
    email: :string,
    website: :string
  }

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope

    cond do
      not Scope.platform_operator?(scope) ->
        {:ok,
         socket
         |> put_flash(:error, "That page is not available in this workspace.")
         |> push_navigate(to: ~p"/dashboard")}

      match?({:ok, _}, Company.platform_operator_company()) ->
        {:ok, company} = Company.platform_operator_company()

        {:ok,
         socket
         |> push_navigate(to: ~p"/companies/#{company.id}")}

      true ->
        {:ok, companies} = Company.list_companies(scope)
        mode = if companies == [], do: :create, else: :select

        {:ok,
         socket
         |> assign(:page_title, "Set Up Platform Operator")
         |> assign(:active_nav, "admin.company")
         |> assign(:companies, companies)
         |> assign(:mode, mode)
         |> assign_form(form_changeset(%{}))}
    end
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in ["select", "create"] do
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
  end

  def handle_event("designate", %{"company_id" => raw_id}, socket) do
    scope = socket.assigns.current_scope.scope

    with {company_id, ""} <- Integer.parse(to_string(raw_id)),
         {:ok, company} <- Company.get_company(scope, company_id),
         {:ok, _} <- Company.assign_primary_company(scope, company.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Platform-operator primary company designated successfully.")
       |> push_navigate(to: ~p"/companies/#{company.id}")}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Select a company in this workspace.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That company is not in this workspace.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, designate_error(reason))}
    end
  end

  def handle_event("create", %{"company" => params}, socket) do
    changeset = form_changeset(params) |> Map.put(:action, :insert)

    if changeset.valid? do
      attrs = create_attrs(changeset)

      case Company.create_company(socket.assigns.current_scope.scope, attrs, is_primary: true) do
        {:ok, company} ->
          {:noreply,
           socket
           |> put_flash(:info, "Platform-operator primary company created successfully.")
           |> push_navigate(to: ~p"/companies/#{company.id}")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="platform-operator-setup" variant={:form}>
        <.header>
          Set Up Platform Operator
          <:subtitle>
            Designate the primary company of the tenant operating this deployment
          </:subtitle>
          <:actions>
            <.button id="platform-operator-back" navigate={~p"/companies"}>Back</.button>
          </:actions>
        </.header>

        <p
          id="platform-operator-notice"
          class="rounded-lg border border-line bg-surface-sunken px-4 py-3 text-sm text-ink-muted"
        >
          The platform operator is the party running this deployment. Its company is
          recorded as the operator tenant’s primary company; numeric tenant and company
          IDs have no special meaning.
        </p>

        <section
          :if={@mode == :select and @companies != []}
          id="platform-operator-select"
          class="rounded-xl border border-line bg-surface px-6 py-5"
        >
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-ink-muted">
            Select Existing Company
          </h2>
          <p class="mt-2 text-xs text-ink-muted">
            Only companies already belonging to the platform-operator tenant can be selected.
          </p>

          <form id="platform-operator-designate-form" phx-submit="designate" class="mt-4 max-w-md space-y-4">
            <label class="block text-sm font-medium text-ink">
              Company
              <select
                id="platform-operator-company"
                name="company_id"
                class="mt-1 block w-full rounded-lg border border-line bg-surface px-3 py-2 text-sm text-ink"
              >
                <option value="">Select a company...</option>
                <option :for={company <- @companies} value={company.id}>
                  {Company.Summary.display_name(company)}
                </option>
              </select>
            </label>
            <.button id="platform-operator-designate" type="submit" variant="primary">
              Set as Primary Company
            </.button>
          </form>

          <p class="mt-4 text-xs text-ink-muted">
            Or
            <button
              id="platform-operator-switch-create"
              type="button"
              phx-click="set_mode"
              phx-value-mode="create"
              class="text-action hover:underline"
            >
              create a new company
            </button>
          </p>
        </section>

        <section
          :if={@mode == :create}
          id="platform-operator-create"
          class="rounded-xl border border-line bg-surface px-6 py-5"
        >
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-ink-muted">
            Create Primary Company
          </h2>

          <.form
            for={@form}
            id="platform-operator-create-form"
            phx-submit="create"
            class="mt-4 space-y-4"
          >
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@form[:name]} id="platform-operator-name" label="Name" required maxlength="255" />
              <.input field={@form[:legal_name]} id="platform-operator-legal-name" label="Legal Name" maxlength="255" />
              <.input
                field={@form[:registration_number]}
                id="platform-operator-registration-number"
                label="Registration Number"
                maxlength="255"
              />
              <.input field={@form[:tax_id]} id="platform-operator-tax-id" label="Tax ID" maxlength="255" />
            </div>
            <div class="grid gap-x-4 sm:grid-cols-3">
              <.input
                field={@form[:jurisdiction]}
                id="platform-operator-jurisdiction"
                label="Jurisdiction"
                maxlength="2"
              />
              <.input field={@form[:email]} id="platform-operator-email" type="email" label="Email" maxlength="255" />
              <.input field={@form[:website]} id="platform-operator-website" label="Website" maxlength="255" />
            </div>
            <.button id="platform-operator-save" type="submit" variant="primary">
              Create Primary Company
            </.button>
          </.form>

          <p :if={@companies != []} class="mt-4 text-xs text-ink-muted">
            Or
            <button
              id="platform-operator-switch-select"
              type="button"
              phx-click="set_mode"
              phx-value-mode="select"
              class="text-action hover:underline"
            >
              select an existing company
            </button>
          </p>
        </section>
      </.page>
    </Layouts.app>
    """
  end

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  defp create_attrs(changeset) do
    name = get_field(changeset, :name)

    %{
      name: name,
      code: code_from_name(name),
      status: "active",
      legal_name: blank_to_nil(get_field(changeset, :legal_name)),
      registration_number: blank_to_nil(get_field(changeset, :registration_number)),
      tax_id: blank_to_nil(get_field(changeset, :tax_id)),
      jurisdiction: blank_to_nil(get_field(changeset, :jurisdiction)),
      email: blank_to_nil(get_field(changeset, :email)),
      website: blank_to_nil(get_field(changeset, :website))
    }
  end

  # Belimbing `Company::creating` slugs a blank code; main's changeset still
  # requires `code` until #370 merges.
  defp code_from_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> String.slice(0, 255)
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp copy_domain_errors(form_changeset, domain_changeset) do
    Enum.reduce(domain_changeset.errors, form_changeset, fn {field, {message, opts}}, acc ->
      add_error(acc, field, message, opts)
    end)
    |> Map.put(:action, :insert)
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :company))
  end

  defp designate_error({:already_assigned, _id}),
    do: "This tenant already has a primary company."

  defp designate_error({:company_tenant_mismatch, _id}),
    do: "That company is not in this workspace."

  defp designate_error(_reason), do: "Could not designate the primary company."
end
