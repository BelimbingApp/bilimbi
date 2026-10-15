defmodule Bilimbi.Core.Person.Web.IndexLive do
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Base.Grid.Web.PageColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Core.Person
  @list_spec ListState.spec!(page_sizes: [25, 50, 100], default_page_size: 25)
  @write_guard_opt_out ~w(grid)
  @impl true
  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Contacts")
     |> assign(:active_nav, "admin.contacts")
     |> assign(
       :columns,
       PageColumns.mount(socket.assigns.current_scope, "core_people", [
         %{id: "full_name", label: "Name", type: :string},
         %{id: "email", label: "Email", type: :string},
         %{id: "phone", label: "Phone", type: :string}
       ])
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    state = ListState.parse(params, @list_spec)
    columns = PageColumns.from_params(socket.assigns.columns, params)

    scope = socket.assigns.current_scope.scope

    {:ok, page} =
      Person.list(scope, search: state.search, page: state.page, page_size: state.page_size)

    {:ok, work_contacts} = Person.work_contacts(scope, Enum.map(page.entries, & &1.id))
    entries = Enum.map(page.entries, &with_work_contact(&1, Map.get(work_contacts, &1.id, %{})))

    {:noreply,
     socket
     |> assign(:records, Map.new(entries, &{&1.id, &1}))
     |> assign(:state, state)
     |> assign(:filters_form, ListState.filters_form(state))
     |> assign(:page_result, %{
       page: page.page,
       page_size: page.page_size,
       total_entries: page.total,
       total_pages: ceil(page.total / page.page_size)
     })
     |> assign(
       :can_create?,
       Bilimbi.Base.Authz.can(socket.assigns.current_scope.scope, "admin.person.create").allowed
     )
     |> assign(:columns, PageColumns.load(columns, entries, & &1.id))}
  end

  defp with_work_contact(person, work) do
    %{person | email: person.email || work[:email], phone: person.phone || work[:phone]}
  end

  @impl true
  def handle_event("filters", %{"filters" => params}, socket),
    do: patch(socket, ListState.apply_filters(socket.assigns.state, params))

  def handle_event("page", %{"page" => page}, socket),
    do: patch(socket, ListState.put_page(socket.assigns.state, page))

  def handle_event("grid", params, socket) do
    case PageColumns.handle(socket.assigns.columns, params) do
      {:patch, columns} -> patch(socket, socket.assigns.state, columns)
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      _ -> {:noreply, socket}
    end
  end

  defp patch(socket, state), do: patch(socket, state, socket.assigns.columns)

  defp patch(socket, state, columns),
    do:
      {:noreply,
       push_patch(socket,
         to: ~p"/contacts?#{Map.merge(ListState.to_params(state), PageColumns.params(columns))}"
       )}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="contacts-index">
        <.header>
          Contacts<:actions>
            <.create_button
              :if={@can_create?}
              id="new-contact"
              noun="Contact"
              navigate={~p"/contacts/new"}
            />
          </:actions>
        </.header>
        <.empty_state :if={!@can_create?} id="contacts-create-forbidden" forbidden="create contacts" />
        <.filter_toolbar id="contacts-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="contacts-search"
            label="Search contacts"
            placeholder="Search name, email or phone"
          />
        </.filter_toolbar>
        <.flex_table
          id="contacts"
          columns={@columns.column_views}
          rows={@columns.rows}
          mode={@columns.mode}
          zoom={@columns.zoom}
          suggestions={@columns.suggestions}
          add_query={@columns.add_query}
          event="grid"
          expanded={@columns.expanded}
          cost={@columns.cost}
          since={@columns.since}
          row_id={&"contact-#{&1}"}
        >
          <:col :let={%{key: id}} id="full_name">
            <% p = Map.fetch!(@records, id) %><.record_link
              workspace={@workspace}
              kind="core/person"
              record_id={p.id}
              navigate={~p"/contacts/#{p.id}"}
            >{p.full_name}</.record_link>
          </:col>
          <:col :let={%{key: id}} id="email">
            <% p = Map.fetch!(@records, id) %><.restricted
              :if={Bilimbi.Base.Authz.Restricted.restricted?(p.email)}
              id={"contact-restricted-email-#{p.id}"}
            /><span :if={!Bilimbi.Base.Authz.Restricted.restricted?(p.email)}>{p.email}</span>
          </:col>
          <:col :let={%{key: id}} id="phone">
            <% p = Map.fetch!(@records, id) %><.restricted
              :if={Bilimbi.Base.Authz.Restricted.restricted?(p.phone)}
              id={"contact-restricted-phone-#{p.id}"}
            /><span :if={!Bilimbi.Base.Authz.Restricted.restricted?(p.phone)}>{p.phone}</span>
          </:col>
          <:empty title="No contacts found" />
        </.flex_table>
        <.pagination
          id="contacts-pagination"
          page={@page_result}
          filters_form={@filters_form}
          page_sizes={[25, 50, 100]}
        />
      </.page>
    </Layouts.app>
    """
  end
end
