defmodule Bilimbi.Core.Company.Web.CreateLive do
  @moduledoc """
  Create-company form. Persistence stays in `Bilimbi.Core.Company.create_company/3`.

  Belimbing: `app/Core/Company/Livewire/Companies/Create.php`.
  """

  use Bilimbi.Base.UI, :live_view

  import Ecto.Changeset

  alias Bilimbi.Core.Company
  alias Ecto.Changeset

  @statuses ~w(active suspended pending archived)

  @field_types %{
    parent_id: :id,
    name: :string,
    code: :string,
    status: :string,
    legal_name: :string,
    registration_number: :string,
    tax_id: :string,
    legal_entity_type_id: :id,
    jurisdiction: :string,
    email: :string,
    website: :string,
    scope_activities_json: :string,
    metadata_json: :string
  }

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope.scope
    {:ok, companies} = Company.list_companies(scope)
    {:ok, types} = Company.list_legal_entity_types()
    countries = Bilimbi.Core.Geonames.list_countries()

    {:ok,
     socket
     |> assign(:page_title, "Create Company")
     |> assign(:active_nav, "admin.company")
     |> assign(:parent_companies, companies)
     |> assign(:legal_entity_types, Enum.filter(types, & &1.is_active))
     |> assign(:countries, countries)
     |> assign_form(form_changeset(%{"status" => "active"}))}
  end

  @impl true
  def handle_event("validate", %{"company" => params}, socket) do
    {:noreply, assign_form(socket, form_changeset(params))}
  end

  def handle_event("save", %{"company" => params}, socket) do
    changeset = form_changeset(params) |> Map.put(:action, :insert)

    with true <- changeset.valid?,
         {:ok, attrs} <- domain_attrs(changeset) do
      case Company.create_company(socket.assigns.current_scope.scope, attrs) do
        {:ok, _company} ->
          {:noreply,
           socket
           |> put_flash(:info, "Company created successfully.")
           |> push_navigate(to: ~p"/companies")}

        {:error, %Changeset{} = domain_changeset} ->
          {:noreply, assign_form(socket, copy_domain_errors(changeset, domain_changeset))}
      end
    else
      false ->
        {:noreply, assign_form(socket, changeset)}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="company-create-page" variant={:form}>
        <.header>
          Create Company
          <:subtitle>Add a company record and business context</:subtitle>
          <:actions>
            <.button id="company-create-back" navigate={~p"/companies"}>
              Back
            </.button>
          </:actions>
        </.header>

        <.form for={@form} id="company-form" phx-change="validate" phx-submit="save" class="space-y-5">
          <section class="rounded-xl border border-line bg-surface px-6 py-5">
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:parent_id]}
                id="company-parent"
                type="select"
                label="Parent Company"
                prompt="None"
                options={parent_options(@parent_companies)}
              />
              <.input
                field={@form[:status]}
                id="company-status"
                type="select"
                label="Status"
                options={status_options()}
                required
              />
              <.input
                field={@form[:name]}
                id="company-name"
                label="Name"
                placeholder="Company display name"
                required
                maxlength="255"
              />
              <.input
                field={@form[:code]}
                id="company-code"
                label="Code"
                placeholder="Auto-generated if blank"
                maxlength="255"
              />
              <.input
                field={@form[:legal_name]}
                id="company-legal-name"
                label="Legal Name"
                placeholder="Registered legal entity name"
                maxlength="255"
              />
              <.input
                field={@form[:legal_entity_type_id]}
                id="company-legal-entity-type"
                type="select"
                label="Legal Entity Type"
                prompt="Select type..."
                options={legal_entity_type_options(@legal_entity_types)}
              />
              <.input
                field={@form[:registration_number]}
                id="company-registration-number"
                label="Registration Number"
                maxlength="255"
              />
              <.input
                field={@form[:tax_id]}
                id="company-tax-id"
                label="Tax ID"
                maxlength="255"
              />
            </div>
            <div class="grid gap-x-4 sm:grid-cols-3">
              <.input
                field={@form[:jurisdiction]}
                id="company-jurisdiction"
                type="select"
                label="Jurisdiction"
                prompt="Select country..."
                options={country_options(@countries)}
              />
              <.input
                field={@form[:email]}
                id="company-email"
                type="email"
                label="Email"
                maxlength="255"
              />
              <.input
                field={@form[:website]}
                id="company-website"
                label="Website"
                placeholder="example.com"
                maxlength="255"
              />
            </div>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:scope_activities_json]}
                id="company-scope-activities"
                type="textarea"
                label="Business Activities (JSON)"
                placeholder={~s({"industry":"Manufacturing"})}
              />
              <.input
                field={@form[:metadata_json]}
                id="company-metadata"
                type="textarea"
                label="Metadata (JSON)"
                placeholder={~s({"employee_count":120})}
              />
            </div>
          </section>

          <div class="flex items-center gap-4">
            <.button id="company-save" type="submit" variant="primary" phx-disable-with="Creating…">
              Create Company
            </.button>
            <.link
              id="company-cancel"
              navigate={~p"/companies"}
              class="text-sm font-medium text-ink-muted hover:text-ink"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </.page>
    </Layouts.app>
    """
  end

  defp form_changeset(params) do
    {%{}, @field_types}
    |> cast(params, Map.keys(@field_types))
    |> validate_required([:name, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:code, max: 255)
    |> validate_length(:jurisdiction, max: 2)
    |> validate_json(:scope_activities_json)
    |> validate_json(:metadata_json)
  end

  defp validate_json(changeset, field) do
    case get_field(changeset, field) do
      value when value in [nil, ""] ->
        changeset

      value when is_binary(value) ->
        case JSON.decode(value) do
          {:ok, decoded} when is_map(decoded) ->
            changeset

          {:ok, _other} ->
            add_error(changeset, field, "must be a JSON object")

          {:error, _} ->
            add_error(changeset, field, "must be valid JSON")
        end

      _other ->
        changeset
    end
  end

  defp domain_attrs(%Changeset{} = changeset) do
    if changeset.valid? do
      {:ok,
       %{
         parent_id: get_field(changeset, :parent_id),
         name: get_field(changeset, :name),
         code: blank_to_nil(get_field(changeset, :code)),
         status: get_field(changeset, :status),
         legal_name: blank_to_nil(get_field(changeset, :legal_name)),
         registration_number: blank_to_nil(get_field(changeset, :registration_number)),
         tax_id: blank_to_nil(get_field(changeset, :tax_id)),
         legal_entity_type_id: get_field(changeset, :legal_entity_type_id),
         jurisdiction: blank_to_nil(get_field(changeset, :jurisdiction)),
         email: blank_to_nil(get_field(changeset, :email)),
         website: blank_to_nil(get_field(changeset, :website)),
         scope_activities: decode_object(get_field(changeset, :scope_activities_json)),
         metadata: decode_object(get_field(changeset, :metadata_json))
       }}
    else
      {:error, changeset}
    end
  end

  defp decode_object(value) when value in [nil, ""], do: nil

  defp decode_object(value) when is_binary(value) do
    {:ok, decoded} = JSON.decode(value)
    decoded
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

  defp parent_options(companies) do
    Enum.map(companies, &{Company.Summary.display_name(&1), &1.id})
  end

  defp legal_entity_type_options(types) do
    Enum.map(types, &{&1.name, &1.id})
  end

  defp country_options(countries) do
    Enum.map(countries, &{"#{&1.country} (#{&1.iso})", &1.iso})
  end

  defp status_options do
    Enum.map(@statuses, &{String.capitalize(&1), &1})
  end
end
