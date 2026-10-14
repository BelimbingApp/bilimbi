defmodule Bilimbi.Core.Person.Web.CreateLive do
  use Bilimbi.Base.UI, :live_view
  import Ecto.Changeset
  alias Bilimbi.Base.UI.FormErrors
  alias Bilimbi.Core.{Company, Person}

  @fields %{
    full_name: :string,
    company_id: :integer,
    title: :string,
    email: :string,
    phone: :string
  }
  @impl true
  def mount(_, _, socket) do
    {:ok, companies} =
      Company.list_selectable_companies(socket.assigns.current_scope.scope, "admin.person.create")

    {:ok,
     socket
     |> assign(:page_title, "New contact")
     |> assign(:active_nav, "admin.contacts")
     |> assign(
       :restricted_fields,
       Enum.uniq(
         Bilimbi.Base.Authz.restricted_fields(socket.assigns.current_scope.scope, "core_people") ++
           Bilimbi.Base.Authz.restricted_fields(
             socket.assigns.current_scope.scope,
             "core_person_affiliations"
           )
       )
     )
     |> assign(:companies, Enum.map(companies, &{&1.name, &1.id}))
     |> form(%{})}
  end

  @impl true
  def handle_event("validate", %{"contact" => attrs}, socket),
    do: {:noreply, form(socket, attrs, :validate)}

  def handle_event("save", %{"contact" => attrs}, socket) do
    cs = changeset(attrs) |> Map.put(:action, :insert)

    if cs.valid? do
      case Person.create_contact(
             socket.assigns.current_scope.scope,
             get_field(cs, :company_id),
             attrs
           ) do
        {:ok, %{person: person}} ->
          {:noreply,
           socket
           |> put_flash(:success, "Contact created.")
           |> push_navigate(to: ~p"/contacts/#{person.id}")}

        {:error, %Ecto.Changeset{} = domain_cs} ->
          {:noreply,
           assign(
             socket,
             :form,
             to_form(FormErrors.copy(cs, domain_cs, action: :insert), as: :contact)
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Contact was not created: #{Person.refusal_message(reason)}")}
      end
    else
      {:noreply, assign(socket, :form, to_form(cs, as: :contact))}
    end
  end

  defp changeset(attrs),
    do:
      {%{}, @fields}
      |> cast(attrs, Map.keys(@fields))
      |> validate_required([:full_name, :company_id])

  defp form(socket, attrs, action \\ nil),
    do: assign(socket, :form, to_form(Map.put(changeset(attrs), :action, action), as: :contact))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:form} id="contact-create">
        <.header>
          New contact<:actions>
            <.back_link id="contact-create-back" navigate={~p"/contacts"} title="Back to contacts" />
          </:actions>
        </.header>
        <.empty_state
          :if={@companies == []}
          id="contact-no-companies"
          title="No company available"
          reason="Create the organisation first, or ask an operator for permission to work with it."
        />
        <.form for={@form} id="contact-form" phx-change="validate" phx-submit="save" class="space-y-4">
          <.input field={@form[:full_name]} id="contact-full-name" label="Full name" required />
          <.input
            field={@form[:company_id]}
            id="contact-company"
            type="select"
            label="Affiliated company"
            options={@companies}
            prompt="Select a company"
            required
          />
          <.restricted_field
            :if={"title" in @restricted_fields}
            id="contact-title-restricted"
            label="Title"
          />
          <.input
            :if={"title" not in @restricted_fields}
            field={@form[:title]}
            id="contact-title"
            label="Title"
          />
          <.restricted_field
            :if={"email" in @restricted_fields}
            id="contact-email-restricted"
            label="Email"
          />
          <.input
            :if={"email" not in @restricted_fields}
            field={@form[:email]}
            id="contact-email"
            label="Email"
          />
          <.restricted_field
            :if={"phone" in @restricted_fields}
            id="contact-phone-restricted"
            label="Phone"
          />
          <.input
            :if={"phone" not in @restricted_fields}
            field={@form[:phone]}
            id="contact-phone"
            label="Phone"
          />
          <.button id="contact-save" variant="primary" type="submit" disabled={@companies == []}>Create contact</.button>
        </.form>
      </.page>
    </Layouts.app>
    """
  end
end
