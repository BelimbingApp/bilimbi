defmodule Bilimbi.Base.Grid.Web.GridLive do
  @moduledoc """
  The grid page: any table of the catalog, with the columns a person walked
  to, read through lenses, at any zoom.

  `/grid` lists the tables the account may read; `/grid/:table` opens one.
  The view is the URL (`Bilimbi.Base.Grid.View`), so a reload or a shared
  link reopens the same grid and Back steps through what was tried. The
  catalog is built once at mount from the scope's capabilities and every
  read goes through it, so a spec that names a table the account may not
  read is dropped with a message rather than run.

  In the full mode the page pages like every other operational list. In the
  compact and carpet modes the hook asks for windows of rows as the person
  scrolls, and only the visible window is queried and sent.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Grid
  alias Bilimbi.Base.Grid.Result
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Grid.Web.Host
  alias Bilimbi.Base.Grid.Zoom

  # Column, lens, zoom, sort and window operations rearrange what the account
  # reads through its own catalog; nothing is written.
  @write_guard_opt_out ~w(grid grid_filters grid_page grid_pick)

  @impl true
  def mount(_params, _session, socket) do
    catalog = Grid.catalog(socket.assigns.current_scope.scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Grid"))
     |> assign(:active_nav, "grid")
     |> assign(:catalog, catalog)
     |> assign(:tables, Grid.tables(catalog))
     |> assign(:table, nil)
     |> assign(:view, %View{})
     |> assign(:columns, [])
     |> assign(:column_views, [])
     |> assign(:result, nil)
     |> assign(:rows, [])
     |> assign(:mode, :full)
     |> assign(:suggestions, [])
     |> assign(:add_query, "")
     |> assign(:expanded, %{})
     |> assign(:window, nil)
     |> assign(:filters_form, to_form(%{"search" => "", "perPage" => 25}, as: :filters))}
  end

  @impl true
  def handle_params(%{"table" => table_id} = params, _uri, socket) do
    case Grid.fetch_table(socket.assigns.catalog, table_id) do
      {:ok, table} ->
        view = View.from_params(params, table.id)
        {:noreply, socket |> assign(:table, table) |> load(view)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("That table is not in your catalog."))
         |> push_navigate(to: ~p"/grid")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket |> assign(:table, nil) |> assign(:page_title, gettext("Grid"))}
  end

  defp load(socket, %View{} = view) do
    %{catalog: catalog, table: table} = socket.assigns
    {columns, dropped} = Host.resolve_columns(catalog, table, view)
    view = %{view | columns: Enum.map(columns, & &1.spec)}
    mode = Zoom.mode(view.zoom)
    sort = Enum.find(columns, &(&1.spec == view.sort))

    result =
      if mode == :full do
        Grid.query(catalog, table, columns,
          offset: (view.page - 1) * view.page_size,
          limit: view.page_size,
          sort: {sort, view.dir},
          search: view.search
        )
      else
        # The hook asks for the window it can show; this run brings the total,
        # the ranges every colour scales to, and the planner's estimate.
        Grid.query(catalog, table, columns,
          offset: 0,
          limit: 1,
          sort: {sort, view.dir},
          search: view.search
        )
      end

    socket =
      socket
      |> assign(:page_title, table.label)
      |> assign(:view, view)
      |> assign(:columns, columns)
      |> assign(:column_views, Host.column_views(columns, view))
      |> assign(:result, result)
      |> assign(:rows, if(mode == :full, do: Host.rows(result, view), else: []))
      |> assign(:mode, mode)
      |> assign(:expanded, %{})
      |> assign(:window, nil)
      |> assign(
        :filters_form,
        to_form(%{"search" => view.search, "perPage" => view.page_size}, as: :filters)
      )

    socket =
      if dropped == [] do
        socket
      else
        put_flash(
          socket,
          :info,
          gettext("Left out: %{specs}. Those columns are not in your catalog.",
            specs: Enum.join(dropped, ", ")
          )
        )
      end

    clamp_page(socket, result, view)
  end

  defp clamp_page(socket, %Result{} = result, %View{} = view) do
    page = Result.page(result)

    cond do
      socket.assigns.mode != :full ->
        socket

      page.total_pages > 0 and view.page > page.total_pages ->
        push_patch(socket, to: path(%{view | page: page.total_pages}))

      page.total_pages == 0 and view.page > 1 ->
        push_patch(socket, to: path(%{view | page: 1}))

      true ->
        socket
    end
  end

  @impl true
  def handle_event("grid", params, socket) do
    %{view: view, columns: columns, catalog: catalog, table: table} = socket.assigns

    case Host.apply(params, view, columns) do
      {:patch, view} ->
        {:noreply,
         socket
         |> assign(:suggestions, [])
         |> assign(:add_query, "")
         |> push_patch(to: path(view))}

      {:suggest, text} ->
        suggestions =
          if text == "", do: [], else: Grid.suggest(catalog, table, text, exclude: view.columns)

        {:noreply,
         socket
         |> assign(:add_query, text)
         |> assign(:suggestions, Host.column_views(suggestions, view))}

      {:add_typed, text, view} ->
        case Grid.resolve(catalog, table, [text]) do
          {:ok, [_column]} ->
            {:noreply,
             socket
             |> assign(:suggestions, [])
             |> assign(:add_query, "")
             |> push_patch(to: path(View.add_column(view, text)))}

          {:error, _reason} ->
            case Grid.suggest(catalog, table, text, exclude: view.columns, limit: 1) do
              [first] ->
                {:noreply,
                 socket
                 |> assign(:suggestions, [])
                 |> assign(:add_query, "")
                 |> push_patch(to: path(View.add_column(view, first.spec)))}

              [] ->
                {:noreply,
                 put_flash(socket, :info, gettext("No column matches “%{text}”.", text: text))}
            end
        end

      {:expand, spec, key} ->
        column = Enum.find(columns, &(&1.spec == spec))
        row_key = row_key(socket, key)
        rows = Host.expansion(catalog, table, row_key, column)

        expanded =
          Map.update(
            socket.assigns.expanded,
            row_key,
            %{column.id => rows},
            &Map.put(&1, column.id, rows)
          )

        {:noreply, assign(socket, :expanded, expanded)}

      {:collapse, spec, key} ->
        row_key = row_key(socket, key)
        column = Enum.find(columns, &(&1.spec == spec))

        expanded =
          Map.update(
            socket.assigns.expanded,
            row_key,
            %{},
            &Map.delete(&1, if(column, do: column.id, else: spec))
          )

        {:noreply, assign(socket, :expanded, expanded)}

      {:window, offset, limit, detail} ->
        sort = Enum.find(columns, &(&1.spec == view.sort))

        result =
          Grid.query(catalog, table, columns,
            offset: offset,
            limit: limit,
            sort: {sort, view.dir},
            search: view.search,
            stats: false,
            cost: false
          )

        result = %{result | stats: socket.assigns.result.stats}

        {:noreply,
         socket
         |> assign(:window, result)
         |> push_event(
           "#{Map.get(params, "id", "grid")}:window",
           Host.window_payload(result, view, detail)
         )}

      {:cell, row, column_id} ->
        {:reply, %{text: cell_text(socket, row, column_id)}, socket}

      {:scroll, view, row, col} ->
        {:noreply,
         socket |> push_patch(to: path(view)) |> push_event("grid:scroll", %{row: row, col: col})}

      :noop ->
        {:noreply, socket}
    end
  end

  def handle_event("grid_filters", %{"filters" => filters}, socket) do
    view = socket.assigns.view

    view = %{
      view
      | search: filters |> Map.get("search", view.search) |> to_string() |> String.slice(0, 255),
        page_size:
          View.from_params(
            %{"per_page" => Map.get(filters, "perPage", view.page_size)},
            view.table
          ).page_size,
        page: 1
    }

    {:noreply, push_patch(socket, to: path(view))}
  end

  def handle_event("grid_page", %{"page" => page}, socket) do
    view = View.from_params(%{"page" => page}, socket.assigns.view.table)
    {:noreply, push_patch(socket, to: path(%{socket.assigns.view | page: view.page}))}
  end

  def handle_event("grid_pick", %{"pick" => %{"table" => table_id}}, socket) do
    case Grid.fetch_table(socket.assigns.catalog, table_id) do
      {:ok, table} -> {:noreply, push_patch(socket, to: ~p"/grid/#{table.id}")}
      :error -> {:noreply, socket}
    end
  end

  # A key arrives as text from the markup; it is matched back to a listed row
  # so the expansion is of a row the page showed, not of any id typed in.
  defp row_key(socket, key) do
    rows =
      if socket.assigns.window, do: socket.assigns.window.rows, else: socket.assigns.result.rows

    case Enum.find(rows, &(to_string(&1.key) == key)) do
      nil -> key
      row -> row.key
    end
  end

  defp cell_text(
         %{assigns: %{window: %Result{} = window, columns: columns}},
         row_index,
         column_id
       ) do
    with true <- row_index >= window.offset,
         row when not is_nil(row) <- Enum.at(window.rows, row_index - window.offset),
         column when not is_nil(column) <- Enum.find(columns, &(&1.id == column_id)) do
      Bilimbi.Base.Grid.Lens.text(Map.get(row.cells, column.id), column)
    else
      _other -> nil
    end
  end

  defp cell_text(_socket, _row, _column), do: nil

  defp path(%View{table: table} = view), do: ~p"/grid/#{table}?#{View.to_params(view)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_nav={@active_nav}>
      <.page id="grid-page" variant={:list}>
        <%= if @table do %>
          <.header>
            {@table.label}
            <:subtitle>
              {gettext("Add a column by walking a link; zoom out to see the whole set at once.")}
            </:subtitle>
            <:actions>
              <.form
                :let={f}
                for={%{"table" => @table.id}}
                as={:pick}
                id="grid-table-picker"
                phx-change="grid_pick"
              >
                <.input
                  field={f[:table]}
                  type="select"
                  id="grid-table-select"
                  label={gettext("Table")}
                  label_class="sr-only"
                  wrapper_class="mb-0"
                  options={Enum.map(@tables, &{&1.label, &1.id})}
                />
              </.form>
            </:actions>
          </.header>

          <.filter_toolbar id="grid-filters" form={@filters_form} event="grid_filters">
            <:control
              type={:search}
              field={@filters_form[:search]}
              id="grid-search"
              label={gettext("Search %{table}", table: @table.label)}
              placeholder={gettext("Search %{table}…", table: String.downcase(@table.label))}
            />
          </.filter_toolbar>

          <.card id="grid-card" inner_class="p-0">
            <div class="p-2">
              <.flex_table
                id="grid"
                columns={@column_views}
                rows={@rows}
                mode={@mode}
                zoom={@view.zoom}
                sort_by={@view.sort}
                sort_dir={@view.dir}
                suggestions={@suggestions}
                add_query={@add_query}
                total={@result.total_entries}
                offset={@result.offset}
                cost={Host.cost(@result)}
                expanded={@expanded}
                group={@view.group}
                caption={@table.label}
              >
                <:empty
                  :if={@view.search != ""}
                  title={gettext("No rows match “%{search}”", search: @view.search)}
                  reason={gettext("Clear the search to see every row.")}
                >
                  <.button id="grid-clear-search" patch={path(%{@view | search: "", page: 1})}>
                    {gettext("Clear search")}
                  </.button>
                </:empty>
                <:empty
                  :if={@view.search == ""}
                  title={gettext("No rows yet")}
                  reason={
                    gettext("Rows of %{table} you may read appear here.",
                      table: String.downcase(@table.label)
                    )
                  }
                />
              </.flex_table>
            </div>
            <.pagination
              :if={@mode == :full}
              id="grid-pagination"
              page={Result.page(@result)}
              page_sizes={View.page_sizes()}
              filters_form={@filters_form}
              filters_event="grid_filters"
              page_event="grid_page"
            />
            <p
              :if={@mode != :full}
              id="grid-window-summary"
              class="border-t border-low-contrast-line px-2 py-2 text-xs text-ink-muted"
            >
              {gettext(
                "%{total} rows by %{columns} columns. Hover a cell for its value; drag a rectangle to zoom into it.",
                total: @result.total_entries,
                columns: length(@columns)
              )}
            </p>
          </.card>
        <% else %>
          <.header>
            {gettext("Grid")}
            <:subtitle>{gettext("Every table you may read, ready to walk.")}</:subtitle>
          </.header>
          <.card id="grid-tables-card" inner_class="p-0">
            <.table id="grid-tables" rows={@tables} framed={false} caption={gettext("Tables")}>
              <:col :let={table} label={gettext("Table")}>
                <.link
                  id={"grid-table-#{table.id}"}
                  navigate={~p"/grid/#{table.id}"}
                  class="font-medium text-ink-strong hover:underline"
                >
                  {table.label}
                </.link>
              </:col>
              <:col :let={table} label={gettext("Fields")} align={:right}>
                <span class="tabular-nums">{length(Bilimbi.Base.Grid.Table.visible_fields(table))}</span>
              </:col>
              <:col :let={table} label={gettext("Links")} align={:right}>
                <span class="tabular-nums">{length(Bilimbi.Base.Grid.Table.links(table))}</span>
              </:col>
              <:empty
                title={gettext("No tables to show")}
                reason={gettext("Your role reads none of the tables in the catalog.")}
              />
            </.table>
          </.card>
        <% end %>
      </.page>
    </Layouts.app>
    """
  end
end
