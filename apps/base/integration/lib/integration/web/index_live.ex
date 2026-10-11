defmodule Bilimbi.Base.Integration.Web.IndexLive do
  @moduledoc false
  use Bilimbi.Base.UI, :live_view
  alias Bilimbi.Base.Integration
  alias Bilimbi.Base.Grid.Web.PageColumns
  alias Bilimbi.Base.UI.ListState

  @write_guard_opt_out ~w(grid)
  @list ListState.spec!(
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          filters: [
            direction: {:one_of, ~w(incoming outgoing), "outgoing"},
            status: {:one_of, ["", "success", "http_error", "connection_error", "unknown"], ""},
            http_status: {:string, ""},
            actor: {:string, ""},
            since: {:string, ""},
            until: {:string, ""}
          ]
        )
  @builtins [
    %{id: "occurred_at", label: "Time", type: :datetime},
    %{id: "operation", label: "Operation", type: :string},
    %{id: "method", label: "Method", type: :string},
    %{id: "host", label: "Host / path", type: :string},
    %{id: "status", label: "Status", type: :integer},
    %{id: "duration_ms", label: "Duration (ms)", type: :integer},
    %{id: "actor", label: "Person / agent", type: :string}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API Exchanges")
     |> assign(:active_nav, "admin.system.integration")
     |> assign(
       :columns,
       PageColumns.mount(socket.assigns.current_scope, "integration-exchanges", @builtins)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    state = ListState.parse(params, @list)

    options =
      [page: state.page, page_size: state.page_size, search: state.search] ++
        Map.to_list(state.filters)

    case Integration.list_page(socket.assigns.current_scope.scope, options) do
      {:ok, page} ->
        columns =
          socket.assigns.columns
          |> PageColumns.from_params(params)
          |> PageColumns.load(page.entries, & &1.id)

        {:noreply,
         socket
         |> assign(:state, state)
         |> assign(:page, page)
         |> assign(:rows, Map.new(page.entries, &{&1.id, &1}))
         |> assign(:columns, columns)
         |> assign(:filters_form, ListState.filters_form(state))}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, "You do not have permission to list API exchanges.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("filters", %{"filters" => values}, socket) do
    state = ListState.apply_filters(socket.assigns.state, values)
    {:noreply, push_patch(socket, to: exchanges_path(state, socket.assigns.columns))}
  end

  def handle_event("page", %{"page" => page}, socket) do
    state = ListState.put_page(socket.assigns.state, page)
    {:noreply, push_patch(socket, to: exchanges_path(state, socket.assigns.columns))}
  end

  def handle_event("grid", params, socket) do
    case PageColumns.handle(socket.assigns.columns, params) do
      {:patch, columns} ->
        {:noreply, push_patch(socket, to: exchanges_path(socket.assigns.state, columns))}

      {:update, columns} ->
        {:noreply, assign(socket, :columns, columns)}

      :noop ->
        {:noreply, socket}

      {:sort, _key} ->
        {:noreply, socket}
    end
  end

  defp tab_path(state, columns, direction),
    do:
      exchanges_path(
        %{state | page: 1, filters: Map.put(state.filters, :direction, direction)},
        columns
      )

  defp exchanges_path(state, columns),
    do:
      ~p"/system/api-exchanges?#{Map.merge(ListState.to_params(state), PageColumns.params(columns))}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="api-exchanges-index">
        <.header>
          API Exchanges<:subtitle>
            Incoming and outgoing calls; bodies are omitted by default
          </:subtitle>
        </.header>
        <.tabs id="exchange-tabs" aria-label="Exchange direction" class="mb-2">
          <:tab
            patch={tab_path(@state, @columns, "outgoing")}
            current={@state.filters.direction == "outgoing"}
          >
            Outgoing
          </:tab>
          <:tab
            patch={tab_path(@state, @columns, "incoming")}
            current={@state.filters.direction == "incoming"}
          >
            Incoming
          </:tab>
        </.tabs>
        <.filter_toolbar id="exchange-filters" form={@filters_form} event="filters">
          <:control
            type={:search}
            field={@filters_form[:search]}
            id="exchange-search"
            label="Host or operation"
            placeholder="Host, path or operation"
          />
          <:control
            type={:select}
            field={@filters_form[:status]}
            id="exchange-status"
            label="Outcome"
            options={[
              {"All outcomes", ""},
              {"Success", "success"},
              {"HTTP error", "http_error"},
              {"Connection error", "connection_error"},
              {"Unknown", "unknown"}
            ]}
          />
          <:control
            type={:search}
            field={@filters_form[:http_status]}
            id="exchange-http-status"
            label="HTTP status"
            placeholder="HTTP status (e.g. 403)"
          />
          <:control
            type={:search}
            field={@filters_form[:actor]}
            id="exchange-actor"
            label="Person or agent ID"
            placeholder="Person or agent ID"
          />
          <:control type={:date} field={@filters_form[:since]} id="exchange-since" label="From (UTC)" />
          <:control
            type={:date}
            field={@filters_form[:until]}
            id="exchange-until"
            label="Through (UTC)"
          />
        </.filter_toolbar>
        <p
          :if={Bilimbi.Base.Tenancy.Scope.platform_operator?(@current_scope.scope)}
          class="mb-2 text-xs text-warning-ink"
        >
          <.icon name="warning" class="size-3.5" />
          Includes all tenants and exchanges with unknown ownership.
        </p>
        <.card id="exchanges-card" inner_class="p-0">
          <.flex_table
            id="exchanges"
            framed={false}
            columns={@columns.column_views}
            rows={@columns.rows}
            mode={@columns.mode}
            zoom={@columns.zoom}
            suggestions={@columns.suggestions}
            add_query={@columns.add_query}
            expanded={@columns.expanded}
            cost={@columns.cost}
            since={@columns.since}
            row_id={&"exchange-#{&1}"}
            caption="API exchanges"
          >
            <:col :let={%{key: id}} id="occurred_at">
              <.datetime id={"exchange-time-#{id}"} value={@rows[id].occurred_at} />
            </:col>
            <:col :let={%{key: id}} id="operation">
              <.record_link
                workspace={@workspace}
                kind="base/integration"
                record_id={id}
                navigate={~p"/system/api-exchanges/#{id}"}
              >{@rows[id].operation}</.record_link>
            </:col>
            <:col :let={%{key: id}} id="method">{@rows[id].method || "—"}</:col>
            <:col :let={%{key: id}} id="host">
              {@rows[id].host || @rows[id].endpoint}<span
                :if={@columns.mode == :normal}
                class="block text-xs text-muted"
              >{@rows[id].path}</span>
            </:col>
            <:col :let={%{key: id}} id="status">
              {@rows[id].response_status || @rows[id].outcome}
            </:col>
            <:col :let={%{key: id}} id="duration_ms">{@rows[id].duration_ms}</:col>
            <:col :let={%{key: id}} id="actor">
              {@rows[id].person_id || @rows[id].agent_id || "System"}
            </:col>
            <:empty>
              <.empty_state title="No API exchanges" reason="No calls match these filters." />
            </:empty>
          </.flex_table>
          <.pagination id="exchanges-pagination" page={@page} filters_form={@filters_form} />
        </.card>
      </.page>
    </Layouts.app>
    """
  end
end
