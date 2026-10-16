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
       |> assign(:pending_unlink, nil)
       |> assign(:active_nav, "admin.contacts")
       |> CommitStatus.init()
       |> loaded(person)
       |> assign(
         :affiliation_restrictions,
         Authz.restricted_fields(socket.assigns.current_scope.scope, "core_person_affiliations")
       )
       |> assign(:company_options, Enum.map(companies, &{&1.name, &1.id}))
       |> assign(:role_options, active_role_options())
       |> assign(:link_form, to_form(%{}, as: :affiliation))
       |> assign(:role_form, to_form(%{}, as: :role))
       |> assign(:role_dialog, nil)
       |> assign(:role_dates_form, nil)}
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

  def handle_event("add_role", %{"role" => attrs}, socket) do
    with {:ok, company_id} <- Params.positive_id(attrs["company_id"]),
         {:ok, _} <-
           Person.create_relationship(
             socket.assigns.current_scope.scope,
             socket.assigns.person.id,
             company_id,
             attrs
           ) do
      {:noreply, reload(socket) |> put_flash(:success, "Role added.")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Role was not added: #{Person.refusal_message(reason)}")}

      :error ->
        {:noreply, put_flash(socket, :error, "Select the company the person is related to.")}
    end
  end

  def handle_event("edit_role", %{"id" => id, "mode" => mode}, socket)
      when mode in ["edit", "end"] do
    with {:ok, id} <- Params.positive_id(id),
         {:ok, rows} <-
           Person.relationships(socket.assigns.current_scope.scope, socket.assigns.person.id),
         %{} = role <- Enum.find(rows, &(&1.id == id)) do
      dates = %{
        "effective_from" => unrestricted(role.effective_from),
        "effective_to" =>
          if(mode == "end", do: Date.utc_today(), else: unrestricted(role.effective_to))
      }

      {:noreply,
       socket
       |> assign(:role_dialog, %{mode: String.to_existing_atom(mode), role: role})
       |> assign(:role_dates_form, to_form(dates, as: :role_dates))}
    else
      _ -> {:noreply, put_flash(socket, :error, "That role is no longer active.")}
    end
  end

  def handle_event("close_role_dialog", _, socket),
    do: {:noreply, assign(socket, role_dialog: nil, role_dates_form: nil)}

  def handle_event("save_role_dates", _, %{assigns: %{role_dialog: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("save_role_dates", %{"role_dates" => attrs}, socket) do
    %{mode: mode, role: role} = socket.assigns.role_dialog
    scope = socket.assigns.current_scope.scope
    person_id = socket.assigns.person.id

    result =
      if mode == :end,
        do: Person.end_relationship(scope, person_id, role.id, attrs),
        else: Person.update_relationship(scope, person_id, role.id, attrs)

    case result do
      {:ok, _} ->
        {:noreply,
         reload(socket)
         |> assign(role_dialog: nil, role_dates_form: nil)
         |> put_flash(
           :success,
           if(mode == :end, do: "Role ended; it stays in history.", else: "Role dates updated.")
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Role was not changed: #{Person.refusal_message(reason)}")}
    end
  end

  def handle_event("request_unlink_role", %{"id" => id}, socket),
    do: request_unlink(socket, :role, id)

  def handle_event("request_unlink", %{"id" => id}, socket),
    do: request_unlink(socket, :affiliation, id)

  def handle_event("cancel_unlink", _, socket),
    do: {:noreply, assign(socket, :pending_unlink, nil)}

  def handle_event("unlink_role", _, socket), do: confirm_unlink(socket, :role)
  def handle_event("unlink", _, socket), do: confirm_unlink(socket, :affiliation)

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
    case Params.positive_id(params["id"]) do
      {:ok, id} ->
        fields =
          Map.new(
            [:title, :email, :phone, :started_on, :ended_on],
            &{"affiliation-#{id}-#{&1}", &1}
          )

        {:noreply,
         CommitStatus.save_field(socket, params, fields,
           can?: Authz.can(socket.assigns.current_scope.scope, "admin.person.update").allowed,
           forbidden: "You do not have permission to update contacts.",
           write: fn s, name, field, value ->
             s
             |> CommitStatus.commit(
               name,
               Person.update_affiliation(
                 s.assigns.current_scope.scope,
                 s.assigns.person.id,
                 id,
                 %{
                   field => value
                 }
               ),
               field: field,
               label: to_string(field),
               submitted: value,
               on_ok: fn changed, _ -> changed end
             )
             |> reload()
           end
         )}

      _ ->
        {:noreply, socket}
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

  defp request_unlink(socket, kind, raw_id) do
    scope = socket.assigns.current_scope.scope
    person_id = socket.assigns.person.id

    with {:ok, id} <- Params.positive_id(raw_id),
         true <- Authz.can(scope, "admin.person.update").allowed,
         {:ok, rows} <- unlink_records(kind, scope, person_id),
         %{} = record <- Enum.find(rows, &(&1.id == id and is_nil(&1.unlinked_at))) do
      {:noreply, assign(socket, :pending_unlink, %{kind: kind, record: record})}
    else
      _ -> {:noreply, put_flash(socket, :error, "That link is not available to unlink.")}
    end
  end

  defp unlink_records(:role, scope, person_id), do: Person.relationships(scope, person_id)
  defp unlink_records(:affiliation, scope, person_id), do: Person.affiliations(scope, person_id)

  # The dialog holds the requested record; a confirm never accepts a replacement id.
  # Clear it before writing so cancellations, failures and repeated submits cannot replay it.
  defp confirm_unlink(
         %{assigns: %{pending_unlink: %{kind: pending_kind, record: record}}} = socket,
         kind
       )
       when pending_kind == kind do
    socket = assign(socket, :pending_unlink, nil)
    scope = socket.assigns.current_scope.scope
    person_id = socket.assigns.person.id

    result =
      case kind do
        :role -> Person.unlink_relationship(scope, person_id, record.id)
        :affiliation -> Person.unlink(scope, person_id, record.id)
      end

    case result do
      {:ok, _} ->
        noun = if kind == :role, do: "Role", else: "Affiliation"
        {:noreply, reload(socket) |> put_flash(:success, "#{noun} unlinked; history preserved.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Person.refusal_message(reason))}
    end
  end

  defp confirm_unlink(socket, _kind), do: {:noreply, socket}

  defp date_text(nil), do: ""
  defp date_text(%Date{} = date), do: Date.to_iso8601(date)

  defp unrestricted(value),
    do: if(Bilimbi.Base.Authz.Restricted.restricted?(value), do: nil, else: value)

  defp active_role_options do
    {:ok, types} = Company.list_active_relationship_types()
    Enum.map(types, &{&1.name, &1.id})
  end

  defp loaded(socket, person) do
    scope = socket.assigns.current_scope.scope
    {:ok, roles} = Person.relationships(scope, person.id, include_unlinked: true)

    socket
    |> Bilimbi.Base.UI.Workspace.announce(%{kind: "core/person", id: person.id})
    |> assign(:person, Map.delete(person, :affiliations))
    |> stream(:affiliations, person.affiliations, reset: true)
    |> stream(:relationships, roles, reset: true)
    |> assign(:page_title, person.full_name)
    |> assign(
      :can_update?,
      Authz.can(scope, "admin.person.update").allowed and is_nil(person.retired_at)
    )
  end

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
            <:col
              :let={a}
              :for={{field, label} <- [started_on: "Started", ended_on: "Ended"]}
              label={label}
            >
              <.inline_edit
                :if={@can_update? and is_nil(a.unlinked_at)}
                id={"affiliation-#{a.id}-#{field}"}
                name={"affiliation-#{a.id}-#{field}"}
                id_value={a.id}
                save_event="save_affiliation"
                value={date_text(Map.fetch!(a, field))}
                label={"#{label} (YYYY-MM-DD)"}
                placeholder="YYYY-MM-DD"
                allow_empty
                status={@field_status["affiliation-#{a.id}-#{field}"]}
              />
              <span :if={!@can_update? or a.unlinked_at != nil}>
                {date_text(Map.fetch!(a, field)) |> then(&if(&1 == "", do: "—", else: &1))}
              </span>
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
                phx-click="request_unlink"
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
            <.input
              field={@link_form[:started_on]}
              id="affiliation-started-on"
              type="date"
              label="Started"
            />
            <.input field={@link_form[:ended_on]} id="affiliation-ended-on" type="date" label="Ended" />
            <.button id="affiliation-link" type="submit">Add affiliation</.button>
          </.form>
        </.card>
        <.card inner_class="p-5 sm:p-6" role="region" aria-labelledby="contact-roles-heading">
          <.section_heading id="contact-roles-heading" title="Company roles" />
          <p class="text-sm text-ink-subtle">
            How a company relates to this person, such as customer or prospect. A role grants no access.
          </p>
          <.table
            id="contact-roles"
            rows={@streams.relationships}
            row_item={fn {_id, r} -> r end}
            row_id={fn {id, _} -> id end}
            framed={false}
          >
            <:col :let={r} label="Company">
              <.link navigate={~p"/companies/#{r.company_id}"}>{r.company_name}</.link>
            </:col>
            <:col :let={r} label="Role">{r.role_label}</:col>
            <:col :let={r} label="Period">
              <span class="text-xs text-ink-subtle">
                <.restricted
                  :if={Bilimbi.Base.Authz.Restricted.restricted?(r.effective_from)}
                  id={"role-restricted-#{r.id}-from"}
                />
                <span :if={!Bilimbi.Base.Authz.Restricted.restricted?(r.effective_from)}>
                  {r.effective_from || "Always"}
                </span>
                {" → "}
                <.restricted
                  :if={Bilimbi.Base.Authz.Restricted.restricted?(r.effective_to)}
                  id={"role-restricted-#{r.id}-to"}
                />
                <span :if={!Bilimbi.Base.Authz.Restricted.restricted?(r.effective_to)}>
                  {r.effective_to || "Present"}
                </span>
              </span>
            </:col>
            <:col :let={r} label="Status">
              <.badge kind={if r.is_active, do: :success, else: :neutral}>
                {cond do
                  r.unlinked_at -> "unlinked"
                  r.is_active -> "active"
                  true -> "inactive"
                end}
              </.badge>
              <span :if={r.unlinked_at} class="block text-xs text-ink-subtle">
                Unlinked <.datetime id={"role-unlinked-#{r.id}"} value={r.unlinked_at} />
              </span>
            </:col>
            <:action :let={r}>
              <.icon_button
                :if={@can_update? and is_nil(r.unlinked_at)}
                id={"edit-role-#{r.id}"}
                icon="edit"
                label="Edit role dates"
                phx-click="edit_role"
                phx-value-id={r.id}
                phx-value-mode="edit"
              />
              <.icon_button
                :if={@can_update? and is_nil(r.unlinked_at)}
                id={"end-role-#{r.id}"}
                icon="stop"
                label="End role"
                phx-click="edit_role"
                phx-value-id={r.id}
                phx-value-mode="end"
              />
              <.icon_button
                :if={@can_update? and is_nil(r.unlinked_at)}
                id={"unlink-role-#{r.id}"}
                icon="unlink"
                label="Unlink (remove a mistaken entry)"
                phx-click="request_unlink_role"
                phx-value-id={r.id}
              />
            </:action>
            <:empty title="No company roles" />
          </.table>
          <.form
            :if={@can_update?}
            for={@role_form}
            id="role-form"
            phx-submit="add_role"
            class="mt-4 space-y-2"
          >
            <.input
              field={@role_form[:company_id]}
              id="role-company"
              type="select"
              label="Company"
              options={@company_options}
              prompt="Select a company"
            />
            <.input
              field={@role_form[:relationship_type_id]}
              id="role-type"
              type="select"
              label="Role of this person toward the company"
              options={@role_options}
              prompt="Select a role"
            />
            <.input
              field={@role_form[:effective_from]}
              id="role-effective-from"
              type="date"
              label="Effective from"
            />
            <.input
              field={@role_form[:effective_to]}
              id="role-effective-to"
              type="date"
              label="Effective to"
            />
            <.button id="role-add" type="submit">Add role</.button>
          </.form>
        </.card>
        <.modal
          :if={@role_dialog}
          id="role-dates-modal"
          title={if @role_dialog.mode == :end, do: "End role", else: "Edit role dates"}
          flash={@flash}
          on_cancel={JS.push("close_role_dialog")}
        >
          <:description>
            {if @role_dialog.mode == :end,
              do:
                "End the #{@role_dialog.role.role_label} role toward #{@role_dialog.role.company_name} on this date. It stays in history.",
              else:
                "Update the dates of the #{@role_dialog.role.role_label} role toward #{@role_dialog.role.company_name}."}
          </:description>
          <.form
            for={@role_dates_form}
            id="role-dates-form"
            phx-submit="save_role_dates"
            class="mt-4 space-y-4"
          >
            <.input
              :if={@role_dialog.mode == :edit}
              field={@role_dates_form[:effective_from]}
              id="role-dates-from"
              type="date"
              label="Effective from"
            />
            <.input
              field={@role_dates_form[:effective_to]}
              id="role-dates-to"
              type="date"
              label={if @role_dialog.mode == :end, do: "Ends on", else: "Effective to"}
            />
            <div class="mt-6 flex justify-end gap-2">
              <.button type="button" phx-click="close_role_dialog">Cancel</.button>
              <.button id="role-dates-save" type="submit" variant="primary">Save</.button>
            </div>
          </.form>
        </.modal>
        <.confirm_dialog
          :if={@pending_unlink}
          id="contact-unlink-confirm"
          consequence={
            if @pending_unlink.kind == :role,
              do:
                "The #{@pending_unlink.record.role_label} role toward #{@pending_unlink.record.company_name} will be unlinked as a mistaken entry.",
              else: "The affiliation with #{@pending_unlink.record.company_name} will be unlinked."
          }
          detail="The person and link history are kept. This link cannot be restored from this page."
          confirm="Unlink"
          working="Unlinking…"
          on_confirm={JS.push(if @pending_unlink.kind == :role, do: "unlink_role", else: "unlink")}
          on_cancel={JS.push("cancel_unlink")}
        />
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
