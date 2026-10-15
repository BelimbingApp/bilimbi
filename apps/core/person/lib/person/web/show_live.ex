defmodule Bilimbi.Core.Person.Web.ShowLive do
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.UI.{CommitStatus, Params}
  alias Bilimbi.Core.{Company, Person}
  @fields %{"full_name" => :full_name, "email" => :email, "phone" => :phone}
  @impl true
  def mount(%{"id" => raw}, _, socket) do
    with {:ok, id} <- Params.positive_id(raw),
         {:ok, person} <- Person.get(socket.assigns.current_scope.scope, id) do
      companies =
        case Company.list_selectable_companies(
               socket.assigns.current_scope.scope,
               "admin.person.update"
             ) do
          {:ok, companies} -> companies
          {:error, :unauthorized} -> []
        end

      {:ok,
       socket
       |> assign(:pending_retire?, false)
       |> assign(:active_nav, "admin.contacts")
       |> CommitStatus.init()
       |> loaded(person)
       |> assign(
         :affiliation_restrictions,
         Authz.restricted_fields(socket.assigns.current_scope.scope, "core_person_affiliations")
       )
       |> assign(:company_options, Enum.map(companies, &{&1.name, &1.id}))
       |> assign(:link_form, to_form(%{}, as: :affiliation))}
    else
      _ ->
        {:ok,
         socket |> put_flash(:error, "Contact not found.") |> push_navigate(to: ~p"/contacts")}
    end
  end

  @impl true
  def handle_event("save_field", params, socket) do
    {:noreply,
     CommitStatus.save_field(socket, params, @fields,
       can?: Authz.can(socket.assigns.current_scope.scope, "admin.person.update").allowed,
       forbidden: "You do not have permission to update contacts.",
       write: &save_fact/4
     )}
  end

  def handle_event("link", %{"affiliation" => attrs}, socket) do
    with {:ok, company_id} <- Params.positive_id(attrs["company_id"]),
         {:ok, _} <-
           Person.link(
             socket.assigns.current_scope.scope,
             socket.assigns.person.id,
             company_id,
             attrs
           ) do
      {:noreply, reload(socket) |> put_flash(:success, "Affiliation added.")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Affiliation was not added: #{Person.refusal_message(reason)}")}

      :error ->
        {:noreply, put_flash(socket, :error, "Select an affiliated company.")}
    end
  end

  def handle_event("unlink", %{"id" => id}, socket) do
    with {:ok, id} <- Params.positive_id(id),
         {:ok, _} <-
           Person.unlink(socket.assigns.current_scope.scope, socket.assigns.person.id, id) do
      {:noreply,
       reload(socket) |> put_flash(:success, "Affiliation unlinked; history preserved.")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, Person.refusal_message(reason))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("request_retire", _, socket),
    do: {:noreply, assign(socket, :pending_retire?, true)}

  def handle_event("cancel_retire", _, socket),
    do: {:noreply, assign(socket, :pending_retire?, false)}

  def handle_event("retire", _, %{assigns: %{pending_retire?: false}} = socket),
    do: {:noreply, socket}

  def handle_event("retire", _, socket) do
    socket = assign(socket, :pending_retire?, false)

    case Person.retire(socket.assigns.current_scope.scope, socket.assigns.person.id) do
      {:ok, _} ->
        {:noreply, reload(socket) |> put_flash(:success, "Contact retired; history preserved.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Person.refusal_message(reason))}
    end
  end

  def handle_event("save_affiliation", params, socket) do
    with {:ok, id} <- Params.positive_id(params["id"]) do
      fields = Map.new([:title, :email, :phone], &{"affiliation-#{id}-#{&1}", &1})

      {:noreply,
       CommitStatus.save_field(socket, params, fields,
         can?: Authz.can(socket.assigns.current_scope.scope, "admin.person.update").allowed,
         forbidden: "You do not have permission to update contacts.",
         write: fn s, name, field, value ->
           CommitStatus.commit(
             s,
             name,
             Person.update_affiliation(s.assigns.current_scope.scope, s.assigns.person.id, id, %{
               field => value
             }),
             field: field,
             label: to_string(field),
             submitted: value,
             on_ok: fn changed, _ -> reload(changed) end
           )
         end
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  defp save_fact(socket, name, field, value) do
    CommitStatus.commit(
      socket,
      name,
      Person.update(socket.assigns.current_scope.scope, socket.assigns.person.id, %{
        field => value
      }),
      submitted: value,
      field: field,
      label: name,
      failures: &Person.refusal_message/1,
      on_ok: fn s, _ -> reload(s) end
    )
  end

  defp reload(socket) do
    {:ok, person} = Person.get(socket.assigns.current_scope.scope, socket.assigns.person.id)
    loaded(socket, person)
  end

  defp loaded(socket, person),
    do:
      socket
      |> Bilimbi.Base.UI.Workspace.announce(%{kind: "core/person", id: person.id})
      |> assign(:person, Map.delete(person, :affiliations))
      |> stream(:affiliations, person.affiliations, reset: true)
      |> assign(:page_title, person.full_name)
      |> assign(
        :can_update?,
        Authz.can(socket.assigns.current_scope.scope, "admin.person.update").allowed and
          is_nil(person.retired_at)
      )

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :fields, @fields)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page variant={:detail} id="contact-show">
        <.header>
          {@person.full_name}
          <:actions>
            <.back_link id="contact-back" navigate={~p"/contacts"} title="Back to contacts" />
          </:actions>
        </.header>
        <.alert :if={@person.retired_at} id="contact-retired" kind={:info}>
          This contact is retired. Identity and affiliation history are preserved.
        </.alert>
        <.empty_state
          :if={!@can_update? and is_nil(@person.retired_at)}
          id="contact-update-forbidden"
          forbidden="update contacts"
        />
        <.card inner_class="p-5 sm:p-6" role="region" aria-labelledby="contact-identity-heading">
          <.section_heading id="contact-identity-heading" title="Identity and contact details" />
          <.list id="contact-facts">
            <:item
              :for={{key, label} <- [{"full_name", "Name"}, {"email", "Email"}, {"phone", "Phone"}]}
              title={label}
              id={"contact-fact-#{key}"}
            >
              <.restricted
                :if={Bilimbi.Base.Authz.Restricted.restricted?(Map.fetch!(@person, @fields[key]))}
                id={"contact-restricted-#{key}"}
              />
              <.inline_edit
                :if={
                  @can_update? and
                    !Bilimbi.Base.Authz.Restricted.restricted?(Map.fetch!(@person, @fields[key]))
                }
                id={"contact-edit-#{key}"}
                name={key}
                value={Map.fetch!(@person, @fields[key])}
                label={label}
                allow_empty={key != "full_name"}
                id_value={@person.id}
                save_event="save_field"
                status={@field_status[key]}
              />
              <span :if={
                !@can_update? and
                  !Bilimbi.Base.Authz.Restricted.restricted?(Map.fetch!(@person, @fields[key]))
              }>{Map.fetch!(@person, @fields[key]) || "—"}</span>
            </:item>
          </.list>
        </.card>
        <.card inner_class="p-5 sm:p-6" role="region" aria-labelledby="contact-affiliations-heading">
          <.section_heading id="contact-affiliations-heading" title="Company affiliations" />
          <.table
            id="contact-affiliations"
            rows={@streams.affiliations}
            row_item={fn {_id, a} -> a end}
            row_id={fn {id, _} -> id end}
            framed={false}
          >
            <:col :let={a} label="Company">
              <.link navigate={~p"/companies/#{a.company_id}"}>{a.company_name}</.link>
            </:col>
            <:col :let={a} label="Title">
              <.restricted
                :if={Bilimbi.Base.Authz.Restricted.restricted?(a.title)}
                id={"affiliation-restricted-#{a.id}-title"}
              />
              <.inline_edit
                :if={
                  @can_update? and is_nil(a.unlinked_at) and
                    !Bilimbi.Base.Authz.Restricted.restricted?(a.title)
                }
                id={"affiliation-#{a.id}-title"}
                name={"affiliation-#{a.id}-title"}
                id_value={a.id}
                save_event="save_affiliation"
                value={a.title}
                label="Title"
                allow_empty
                status={@field_status["affiliation-#{a.id}-title"]}
              />
              <span :if={
                (!@can_update? or a.unlinked_at != nil) and
                  !Bilimbi.Base.Authz.Restricted.restricted?(a.title)
              }>{a.title || "—"}</span>
            </:col>
            <:col :let={a} label="Email">
              <.restricted
                :if={Bilimbi.Base.Authz.Restricted.restricted?(a.email)}
                id={"affiliation-restricted-#{a.id}-email"}
              />
              <.inline_edit
                :if={
                  @can_update? and is_nil(a.unlinked_at) and
                    !Bilimbi.Base.Authz.Restricted.restricted?(a.email)
                }
                id={"affiliation-#{a.id}-email"}
                name={"affiliation-#{a.id}-email"}
                id_value={a.id}
                save_event="save_affiliation"
                value={a.email}
                label="Email"
                allow_empty
                status={@field_status["affiliation-#{a.id}-email"]}
              />
              <span :if={
                (!@can_update? or a.unlinked_at != nil) and
                  !Bilimbi.Base.Authz.Restricted.restricted?(a.email)
              }>{a.email || "—"}</span>
            </:col>
            <:col :let={a} label="Phone">
              <.restricted
                :if={Bilimbi.Base.Authz.Restricted.restricted?(a.phone)}
                id={"affiliation-restricted-#{a.id}-phone"}
              />
              <.inline_edit
                :if={
                  @can_update? and is_nil(a.unlinked_at) and
                    !Bilimbi.Base.Authz.Restricted.restricted?(a.phone)
                }
                id={"affiliation-#{a.id}-phone"}
                name={"affiliation-#{a.id}-phone"}
                id_value={a.id}
                save_event="save_affiliation"
                value={a.phone}
                label="Phone"
                allow_empty
                status={@field_status["affiliation-#{a.id}-phone"]}
              />
              <span :if={
                (!@can_update? or a.unlinked_at != nil) and
                  !Bilimbi.Base.Authz.Restricted.restricted?(a.phone)
              }>{a.phone || "—"}</span>
            </:col>
            <:col :let={a} label="Affiliation">
              <span :if={!a.unlinked_at}>Linked</span><span :if={a.unlinked_at}>Unlinked</span>
            </:col>
            <:action :let={a}>
              <.icon_button
                :if={@can_update? and is_nil(a.unlinked_at)}
                id={"unlink-affiliation-#{a.id}"}
                icon="unlink"
                label="Unlink affiliation"
                phx-click="unlink"
                phx-value-id={a.id}
              />
            </:action>
            <:empty title="No affiliations" />
          </.table>
          <.form
            :if={@can_update?}
            for={@link_form}
            id="affiliation-form"
            phx-submit="link"
            class="mt-4 space-y-2"
          >
            <.input
              field={@link_form[:company_id]}
              id="affiliation-company"
              type="select"
              label="Affiliated company"
              options={@company_options}
              prompt="Select a company"
            />
            <.restricted_field
              :if={"title" in @affiliation_restrictions}
              id="affiliation-title-restricted"
              label="Title"
            />
            <.input
              :if={"title" not in @affiliation_restrictions}
              field={@link_form[:title]}
              id="affiliation-title"
              label="Title"
            />
            <.restricted_field
              :if={"email" in @affiliation_restrictions}
              id="affiliation-email-restricted"
              label="Email"
            />
            <.input
              :if={"email" not in @affiliation_restrictions}
              field={@link_form[:email]}
              id="affiliation-email"
              label="Email"
            />
            <.restricted_field
              :if={"phone" in @affiliation_restrictions}
              id="affiliation-phone-restricted"
              label="Phone"
            />
            <.input
              :if={"phone" not in @affiliation_restrictions}
              field={@link_form[:phone]}
              id="affiliation-phone"
              label="Phone"
            />
            <.button id="affiliation-link" type="submit">Add affiliation</.button>
          </.form>
        </.card>
        <.button :if={@can_update?} id="contact-retire" phx-click="request_retire">Retire contact</.button>
        <.confirm_dialog
          :if={@pending_retire?}
          id="contact-retire-confirm"
          consequence="This contact will leave active searches and become read-only."
          detail="Identity, affiliations and existing HR and account references are preserved. Retirement cannot be undone here."
          confirm="Retire"
          working="Retiring…"
          on_confirm={JS.push("retire")}
          on_cancel={JS.push("cancel_retire")}
        />
      </.page>
    </Layouts.app>
    """
  end
end
