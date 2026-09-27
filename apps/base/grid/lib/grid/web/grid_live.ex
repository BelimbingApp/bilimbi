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
  alias Bilimbi.Base.Grid.SavedViews
  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Grid.Web.Host
  alias Bilimbi.Base.Grid.Zoom
  alias Bilimbi.Base.Settings

  # Column, lens, zoom, sort and window operations rearrange what the account
  # reads through its own catalog; nothing is written. Saving or deleting an
  # own view is a self-service write to the actor's own user settings scope,
  # as a workspace layout is; a shared view is guarded by the company
  # settings capability inside the handler.
  @write_guard_opt_out ~w(grid grid_filters grid_page grid_pick open-save close-save save-view
                          request-delete-view cancel-delete-view delete-view)

  @share_capability "base.settings.company.manage"

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
     |> assign(:filters_form, to_form(%{"search" => "", "perPage" => 25}, as: :filters))
     |> assign(:settings_scope, settings_scope(socket.assigns.current_scope))
     |> assign(:company_scope, company_scope(socket.assigns.current_scope))
     |> assign(:can_share?, allowed?(socket.assigns.current_scope, @share_capability))
     |> assign(:saved_own, [])
     |> assign(:saved_shared, [])
     |> assign(:save_open?, false)
     |> assign(:save_form, to_form(%{"label" => "", "shared" => "false"}, as: :view))
     |> assign(:pending_delete, nil)}
  end

  defp settings_scope(current_scope) do
    Settings.Scope.user(
      current_user_id(current_scope),
      current_scope.user["company_id"],
      current_scope.scope.tenant.id
    )
  end

  defp company_scope(%{user: %{"company_id" => company_id}, scope: scope})
       when is_integer(company_id),
       do: Settings.Scope.company(company_id, scope.tenant.id)

  defp company_scope(_current_scope), do: nil

  @impl true
  def handle_params(%{"table" => table_id} = params, _uri, socket) do
    case Grid.fetch_table(socket.assigns.catalog, table_id) do
      {:ok, table} ->
        socket = socket |> assign(:table, table) |> load_saved()
        {view, socket} = view_from_params(socket, params, table)
        {:noreply, load(socket, view)}

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

  # `v` opens a saved view whole; every other param is one unsaved view.
  defp view_from_params(socket, %{"v" => reference} = params, table)
       when is_binary(reference) and reference != "" do
    case fetch_saved(socket, table.id, reference) do
      {:ok, entry, _kind} ->
        {SavedViews.view(entry), socket}

      :error ->
        {View.from_params(Map.delete(params, "v"), table.id),
         put_flash(socket, :error, gettext("That saved view no longer exists."))}
    end
  end

  defp view_from_params(socket, params, table), do: {View.from_params(params, table.id), socket}

  defp fetch_saved(%{assigns: %{settings_scope: own, company_scope: nil}}, table_id, reference) do
    if String.starts_with?(reference, "shared:"),
      do: :error,
      else: SavedViews.fetch(own, Settings.Scope.company(0, 0), table_id, reference)
  end

  defp fetch_saved(
         %{assigns: %{settings_scope: own, company_scope: company}},
         table_id,
         reference
       ) do
    SavedViews.fetch(own, company, table_id, reference)
  end

  defp load_saved(%{assigns: %{table: table}} = socket) do
    own = SavedViews.list_own(socket.assigns.settings_scope, table.id)

    shared =
      case socket.assigns.company_scope do
        nil -> []
        company -> SavedViews.list_shared(company, table.id)
      end

    socket |> assign(:saved_own, own) |> assign(:saved_shared, shared)
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

  def handle_event("open-save", _params, socket) do
    label = if entry = current_entry(socket), do: entry["label"], else: ""

    {:noreply,
     socket
     |> assign(:save_open?, true)
     |> assign(:save_form, to_form(%{"label" => label, "shared" => "false"}, as: :view))}
  end

  def handle_event("close-save", _params, socket),
    do: {:noreply, assign(socket, :save_open?, false)}

  def handle_event("save-view", %{"view" => %{"label" => label} = params}, socket) do
    shared? = Map.get(params, "shared") == "true"

    cond do
      shared? and not allowed?(socket.assigns.current_scope, @share_capability) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You do not have permission to share views with the company.")
         )}

      shared? and is_nil(socket.assigns.company_scope) ->
        {:noreply,
         put_flash(socket, :error, gettext("Your account belongs to no company to share with."))}

      true ->
        {scope, kind} =
          if shared?,
            do: {socket.assigns.company_scope, :shared},
            else: {socket.assigns.settings_scope, :own}

        case SavedViews.save(scope, kind, label, socket.assigns.view) do
          {:ok, entry} ->
            {:noreply,
             socket
             |> assign(:save_open?, false)
             |> put_flash(:success, gettext("View “%{label}” saved.", label: entry["label"]))
             |> push_patch(
               to: ~p"/grid/#{socket.assigns.table.id}?#{%{v: SavedViews.reference(entry, kind)}}"
             )}

          {:error, :label} ->
            {:noreply,
             put_flash(socket, :error, gettext("A view needs a name of at most 60 characters."))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("The view could not be saved."))}
        end
    end
  end

  def handle_event("request-delete-view", %{"ref" => reference}, socket) do
    case fetch_saved(socket, socket.assigns.table.id, reference) do
      {:ok, entry, kind} ->
        {:noreply, assign(socket, :pending_delete, {entry, kind})}

      :error ->
        {:noreply, put_flash(socket, :error, gettext("That saved view no longer exists."))}
    end
  end

  def handle_event("cancel-delete-view", _params, socket),
    do: {:noreply, assign(socket, :pending_delete, nil)}

  def handle_event("delete-view", _params, socket) do
    case socket.assigns.pending_delete do
      nil ->
        {:noreply, socket}

      {_entry, :shared} = pending when not is_nil(pending) ->
        if allowed?(socket.assigns.current_scope, @share_capability) do
          delete_pending(socket, pending)
        else
          {:noreply,
           socket
           |> assign(:pending_delete, nil)
           |> put_flash(
             :error,
             gettext("You do not have permission to delete views shared with the company.")
           )}
        end

      {_entry, :own} = pending ->
        delete_pending(socket, pending)
    end
  end

  defp delete_pending(socket, {entry, kind}) do
    scope =
      if kind == :shared, do: socket.assigns.company_scope, else: socket.assigns.settings_scope

    table = socket.assigns.table

    case SavedViews.delete(scope, kind, table.id, entry["slug"]) do
      :ok ->
        socket =
          socket
          |> assign(:pending_delete, nil)
          |> put_flash(:success, gettext("View “%{label}” deleted.", label: entry["label"]))
          |> load_saved()

        if socket.assigns.view.slug == entry["slug"],
          do: {:noreply, push_patch(socket, to: path(%{socket.assigns.view | slug: nil}))},
          else: {:noreply, socket}

      :error ->
        {:noreply,
         socket
         |> assign(:pending_delete, nil)
         |> put_flash(:error, gettext("That saved view no longer exists."))}
    end
  end

  defp current_entry(%{assigns: %{view: %View{slug: nil}}}), do: nil

  defp current_entry(%{assigns: %{view: %View{slug: slug}, saved_own: own, saved_shared: shared}}) do
    Enum.find(own ++ shared, &(&1["slug"] == slug))
  end

  # A tile is a page at its own address; the workspace reads one leaf as
  # its whole tree, encoded as `Bilimbi.Base.Tiling.Layout` writes a leaf.
  defp tile_path(table_id, reference) do
    path = ~p"/grid/#{table_id}?#{%{v: reference}}"

    ~p"/workspace?#{%{t: URI.encode(path, &(&1 not in [?(, ?), ?,, ?%] and URI.char_unescaped?(&1)))}}"
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

  # A patch from a gesture is an unsaved change, so it leaves the saved
  # view's name behind; opening a saved view is done by `v` alone.
  defp path(%View{table: table} = view),
    do: ~p"/grid/#{table}?#{View.to_params(%{view | slug: nil})}"

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
              <.grid_views_menu
                table={@table}
                own={@saved_own}
                shared={@saved_shared}
                current={@view.slug}
                can_share?={@can_share?}
              />
              <.button id="grid-save-view" phx-click="open-save">
                <.icon name="save" class="size-4" /> {gettext("Save view")}
              </.button>
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
          <.modal
            :if={@save_open?}
            id="grid-save-dialog"
            title={gettext("Save this view")}
            on_cancel={JS.push("close-save")}
          >
            <:description>
              {gettext(
                "The columns, lenses, zoom, sort, search and grouping as they are now, under a name you can reopen or share."
              )}
            </:description>
            <.form for={@save_form} id="grid-save-form" phx-submit="save-view">
              <.input
                field={@save_form[:label]}
                id="grid-save-label"
                label={gettext("Name")}
                maxlength="60"
                required
                autocomplete="off"
              />
              <.input
                :if={@can_share? and @company_scope}
                field={@save_form[:shared]}
                id="grid-save-shared"
                type="checkbox"
                label={gettext("Share with everyone in the company")}
              />
              <div class="flex justify-end gap-2">
                <.button id="grid-save-cancel" type="button" phx-click="close-save">
                  {gettext("Cancel")}
                </.button>
                <.button id="grid-save-submit" type="submit" variant="primary">{gettext("Save")}</.button>
              </div>
            </.form>
          </.modal>
          <.confirm_dialog
            :if={@pending_delete}
            id="grid-delete-view-confirm"
            consequence={
              gettext("The view “%{label}” will be deleted.",
                label: elem(@pending_delete, 0)["label"]
              )
            }
            detail={gettext("Links to it stop opening it. The rows themselves are untouched.")}
            confirm={gettext("Delete")}
            working={gettext("Deleting…")}
            on_confirm={JS.push("delete-view")}
            on_cancel={JS.push("cancel-delete-view")}
          />
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

  attr(:table, :map, required: true)
  attr(:own, :list, required: true)
  attr(:shared, :list, required: true)
  attr(:current, :string, default: nil)
  attr(:can_share?, :boolean, default: false)

  # The saved views of this table: the account's own, then the company's.
  # Each opens by patch, can be opened in a workspace tile, and is deleted
  # through the shared confirmation. The disclosure closes on Escape or when
  # focus leaves, like the tile menu.
  defp grid_views_menu(assigns) do
    menu = "grid-views"
    dismiss = JS.set_attribute({"aria-expanded", "false"}, to: "##{menu}")

    assigns =
      assigns
      |> assign(:menu, menu)
      |> assign(:dismiss, dismiss)
      |> assign(:escape, JS.focus(dismiss, to: "##{menu}"))
      |> assign(:toggle, JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{menu}"))
      |> assign(
        :entries,
        Enum.map(assigns.own, &{&1, :own}) ++ Enum.map(assigns.shared, &{&1, :shared})
      )

    ~H"""
    <div
      id={"#{@menu}-wrap"}
      phx-hook="DisclosureDismiss"
      data-dismiss={@dismiss}
      data-escape={@escape}
      phx-click-away={@dismiss}
      class="relative"
    >
      <.button
        id={@menu}
        type="button"
        aria-expanded="false"
        aria-controls={"#{@menu}-items"}
        phx-click={@toggle}
        class="peer"
      >
        <.icon name="columns" class="size-4" /> {gettext("Views")}
        <span :if={@entries != []} class="tabular-nums text-ink-muted">({length(@entries)})</span>
      </.button>
      <div
        id={"#{@menu}-items"}
        class="hidden peer-aria-expanded:block absolute right-0 top-full z-30 mt-1 min-w-72 rounded-md border border-line bg-surface p-1 shadow-lg"
      >
        <p :if={@entries == []} id="grid-views-empty" class="px-2 py-1 text-xs text-ink-muted">
          {gettext("No saved views for this table yet. Save the current one to keep it.")}
        </p>
        <div :for={{entry, kind} <- @entries} class="flex items-center gap-1">
          <.link
            id={"grid-view-#{kind}-#{entry["slug"]}"}
            patch={~p"/grid/#{@table.id}?#{%{v: SavedViews.reference(entry, kind)}}"}
            phx-click={@dismiss}
            class={[
              "block min-w-0 flex-1 truncate rounded-sm px-2 py-1 text-left text-xs hover:bg-surface-muted",
              @current == entry["slug"] && "text-brand-strong",
              @current != entry["slug"] && "text-ink"
            ]}
          >
            {entry["label"]}
            <span :if={kind == :shared} class="ml-1 text-ink-faint">{gettext("shared")}</span>
          </.link>
          <.icon_button
            icon="fullscreen"
            context={:inline}
            label={gettext("Open “%{label}” in a workspace tile", label: entry["label"])}
            id={"grid-view-#{kind}-#{entry["slug"]}-tile"}
            navigate={tile_path(@table.id, SavedViews.reference(entry, kind))}
          />
          <.icon_button
            :if={kind == :own or @can_share?}
            icon="delete"
            context={:inline}
            kind={:danger}
            label={gettext("Delete “%{label}”", label: entry["label"])}
            id={"grid-view-#{kind}-#{entry["slug"]}-delete"}
            phx-click={
              %JS{
                ops:
                  JS.push("request-delete-view", value: %{ref: SavedViews.reference(entry, kind)}).ops ++
                    @dismiss.ops
              }
            }
          />
        </div>
      </div>
    </div>
    """
  end
end
