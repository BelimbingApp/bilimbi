defmodule Bilimbi.Base.Tiling.Web.WorkspaceLive do
  @moduledoc """
  The tiled workspace at `/workspace`: several Bilimbi pages side by side in
  one browser tab, arranged by `Bilimbi.Base.Tiling.Layout`.

  Each tile is a same-origin frame showing an existing page at its own URL,
  so the page runs as its own root LiveView with its own URL state, patches,
  flash and capability check, exactly as when opened alone. The shell
  renders it chromeless because `BilimbiWeb.FramedRender` marks the frame's
  requests. This page holds only the tree, the focused tile, monocle, the
  titles the frames report, and the account's saved layouts; it never reads
  a page's state.

  The tree is always in the URL: `?t=` carries the ad-hoc layout after every
  change, so Back and Forward work at the workspace level and a copied URL
  reproduces the screen. `/workspace/:slug` opens a saved layout, and
  `/workspace` alone opens the account's default one, else the page picker.

  `?open=` is how a page is tiled in place. The sidebar's tile control on
  any page links to `/workspace?t=<that page>&inplace=1&open=<the clicked
  page>`, and from this page to its own address plus `open=…`, so the one
  URL form serves both entries: the tree in `t` is read as usual, the page in
  `open` takes half of the largest tile, and the URL is replaced by the
  resulting tree. `inplace=1` marks a workspace entered from a page; every
  address this page writes keeps it, except a saved layout's, so across a
  refresh or a reconnect such a workspace still leaves for that page's own
  URL when closed down to one tile, reversible the way it was entered. One
  opened from the picker or a saved layout stays a workspace with one tile.

  The `Tiling` hook owns what the server cannot: the keyboard bridge into
  each frame, the `Ctrl+.` tiling mode, drag resizing, and reporting each
  frame's URL and title. Every keyboard operation is also on the tile menu
  or a split handle, so the mode is a shortcut and never the only path.

  A tile whose page the account may not open shows the permission refusal
  in place of the frame, judged by the same route policy the page's mount
  applies, so a saved layout that outlives a role change says so plainly
  instead of showing a redirect inside the tile.

  Tiles talk through the follow channel, `Bilimbi.Base.UI.Workspace`. This
  page derives the workspace token from its own LiveView id, puts it in
  every frame's URL, and subscribes to the topic. A tile showing a record's
  page can follow selections: it keeps the route pattern of that page
  (`/companies/:id`) in the tree, and when a page in another tile announces
  a record of the module that owns that pattern, this host fills the id in
  and tells the hook to send the frame there. The kinds the tiles follow
  are broadcast to every page in the workspace after each change, so a
  list whose kind is followed selects instead of navigating.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tiling.Layout
  alias Bilimbi.Base.Tiling.SavedLayouts
  alias Bilimbi.Base.Tiling.SharedLayouts
  alias Bilimbi.Base.UI.Nav
  alias Bilimbi.Base.UI.RouteContract
  alias Bilimbi.Base.UI.Workspace

  # Every event here changes the signed-in account's own workspace: the tree
  # it is looking at and the layouts it saved for itself. They are
  # self-service writes to the actor's own user settings scope, as the
  # dashboard's are; no administration capability applies.
  @write_guard_opt_out ~w(add-tile close-tile move-tile swap-tile toggle-monocle toggle-split
                          resize-split nudge-split resize-step save-layout update-layout
                          rename-layout delete-layout confirm-delete-layout set-default-layout
                          clear-default-layout copy-layout)

  # The root layout's title suffix, stripped from what a frame reports so
  # the tile bar shows the page's own name. Keep in step with
  # apps/base/ui/lib/ui/layouts/root.html.heex.
  @title_suffix " · Business application platform"

  @sides %{"left" => :left, "right" => :right, "up" => :up, "down" => :down}
  @full_place "left: 0%; top: 0%; width: 100%; height: 100%"

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope
    token = Workspace.host_token(socket.id)
    topic = Workspace.topic_for(current_scope, token)

    if connected?(socket) and is_binary(topic), do: Workspace.subscribe(topic)

    {:ok,
     socket
     |> assign(:page_title, gettext("Workspace"))
     |> assign(:active_nav, "workspace")
     |> assign(:framed?, current_scope[:framed] == true)
     |> assign(:settings_scope, settings_scope(current_scope))
     |> assign(:company_scope, company_scope(current_scope))
     |> assign(:role_codes, role_codes(current_scope))
     |> assign(:pages, pages(current_scope))
     |> assign(:token, token)
     |> assign(:topic, topic)
     |> assign(:follows, [])
     |> assign(:tree, Layout.empty())
     |> assign(:encoded, nil)
     |> assign(:slug, nil)
     |> assign(:in_place?, false)
     |> assign(:shared?, false)
     |> assign(:focused, nil)
     |> assign(:monocle, false)
     |> assign(:viewport, {1600, 900})
     |> assign(:titles, %{})
     |> assign(:picker_for, nil)
     |> assign(:picker_open?, false)
     |> assign(:layouts_open?, false)
     |> assign(:pending_delete, nil)
     |> assign(:save_form, to_form(%{"label" => ""}, as: :layout))
     |> load_saved()
     |> derive()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    shared? = String.starts_with?(URI.parse(uri).path, "/workspace/shared/")
    socket =
      assign(socket,
        slug: params["slug"],
        shared?: shared?,
        in_place?: params["inplace"] == "1" and not is_binary(params["slug"])
      )

    cond do
      socket.assigns.framed? ->
        {:noreply, socket}

      is_binary(params["open"]) ->
        {:noreply, socket |> load_tree(params) |> open_page(params["open"])}

      shared? and is_binary(params["slug"]) ->
        {:noreply, open_shared(socket, params["slug"], params["t"])}

      is_binary(params["slug"]) ->
        {:noreply, open_saved(socket, params["slug"], params["t"])}

      is_binary(params["t"]) ->
        {:noreply, apply_encoded(socket, params["t"])}

      true ->
        open_default(socket)
    end
  end

  # The tree an `open` request starts from: the saved layout at the slug, the
  # tree in `t`, or nothing.
  defp load_tree(%{assigns: %{shared?: true}} = socket, %{"slug" => slug} = params)
       when is_binary(slug),
       do: open_shared(socket, slug, params["t"])

  defp load_tree(socket, %{"slug" => slug} = params) when is_binary(slug),
    do: open_saved(socket, slug, params["t"])

  defp load_tree(socket, params), do: apply_encoded(socket, params["t"] || "")

  # A patch this page pushed itself carries the tree it already holds.
  defp apply_encoded(%{assigns: %{encoded: encoded}} = socket, encoded), do: socket

  defp apply_encoded(socket, encoded) do
    case Layout.decode(encoded) do
      {:ok, incoming} ->
        layout = Layout.reconcile(socket.assigns.tree, incoming)
        socket |> put_layout(layout) |> assign(:encoded, encoded) |> keep_focus()

      :error ->
        socket
        |> put_flash(
          :error,
          gettext("The layout in the address could not be read, so the workspace opened empty.")
        )
        |> put_layout(Layout.empty())
        |> assign(:encoded, nil)
        |> keep_focus()
    end
  end

  defp open_saved(socket, slug, encoded) do
    case SavedLayouts.fetch(socket.assigns.settings_scope, slug) do
      {:ok, entry} ->
        apply_encoded(socket, encoded || entry["tree"])

      :error ->
        socket
        |> put_flash(:error, gettext("There is no saved layout called “%{slug}”.", slug: slug))
        |> push_navigate(to: ~p"/workspace")
    end
  end

  defp open_shared(socket, slug, encoded) do
    case SharedLayouts.fetch_visible(
           socket.assigns.company_scope,
           slug,
           socket.assigns.role_codes
         ) do
      {:ok, entry} ->
        apply_encoded(socket, encoded || entry["tree"])

      :error ->
        socket
        |> put_flash(:error, gettext("This shared workspace is not available."))
        |> push_navigate(to: ~p"/workspace")
    end
  end

  defp open_default(socket) do
    case SavedLayouts.default_slug(socket.assigns.settings_scope) do
      nil ->
        socket = socket |> put_layout(Layout.empty()) |> assign(:encoded, nil) |> keep_focus()
        {:noreply, assign(socket, picker_open?: Layout.empty?(socket.assigns.tree))}

      slug ->
        {:noreply, push_navigate(socket, to: ~p"/workspace/#{slug}")}
    end
  end

  # Tiles `path` in place: it takes half of the largest tile, and the URL is
  # replaced by the tree that results, so `open` is never left in the
  # address to be replayed by a refresh. It accepts what a tile shows, a
  # served page this account may open, except the workspace itself.
  defp open_page(%{redirected: nil} = socket, path) do
    if tile_path?(path) and not workspace_page?(path) and
         access(socket.assigns.current_scope, path) == :ok do
      socket |> tile_page(path, :largest) |> sync_url(replace: true)
    else
      socket
      |> put_flash(:error, gettext("%{path} cannot be opened in a tile.", path: path))
      |> sync_url(replace: true)
    end
  end

  defp open_page(socket, _path), do: socket

  defp tile_page(socket, path, at) do
    {layout, id} =
      Layout.open(socket.assigns.tree, path, at: at, viewport: socket.assigns.viewport)

    socket
    |> put_layout(layout)
    |> assign(picker_open?: false, picker_for: nil, monocle: false)
    |> focus(id)
  end

  # ------------------------------------------------------------------
  # Events from the hook
  # ------------------------------------------------------------------

  @impl true
  def handle_event("viewport", %{"w" => w, "h" => h}, socket)
      when is_number(w) and is_number(h) and w > 0 and h > 0 do
    {:noreply, assign(socket, :viewport, {w, h})}
  end

  def handle_event("viewport", _params, socket), do: {:noreply, socket}

  def handle_event("tile-navigated", %{"id" => id, "path" => path} = params, socket)
      when is_binary(path) do
    with %{} <- Layout.fetch_leaf(socket.assigns.tree, id),
         true <- tile_path?(path),
         path <- Workspace.strip_token(path) do
      title = params |> Map.get("title") |> clean_title()

      socket =
        socket
        |> update(:titles, &Map.put(&1, id, title))
        |> put_layout(Layout.update_path(socket.assigns.tree, id, path))

      {:noreply, sync_url(socket, replace: true)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("focus-tile", %{"id" => id}, socket) do
    {:noreply, focus(socket, id)}
  end

  # The narrow-screen tab strip is `<.tabs>`, which names its value `tab`.
  def handle_event("focus-tile", %{"tab" => id}, socket) do
    {:noreply, focus(socket, id)}
  end

  def handle_event("focus-direction", %{"side" => side}, socket) do
    with {:ok, side} <- side(side),
         id when is_binary(id) <- socket.assigns.focused,
         other when is_binary(other) <- Layout.neighbor(socket.assigns.tree, id, side) do
      {:noreply, focus(socket, other)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move-tile", %{"id" => id, "side" => side}, socket) do
    case side(side) do
      {:ok, side} ->
        {:noreply, socket |> put_layout(Layout.move(socket.assigns.tree, id, side)) |> sync_url()}

      :error ->
        {:noreply, socket}
    end
  end

  # `with` names the tile a drag dropped this one on; `side` the neighbour
  # the keyboard mode chose; neither means the nearest neighbour.
  def handle_event("swap-tile", %{"id" => id} = params, socket) do
    layout = socket.assigns.tree

    partner =
      case {params["with"], side(params["side"])} do
        {other, _} when is_binary(other) -> current_leaf(layout, other)
        {_, {:ok, side}} -> Layout.neighbor(layout, id, side)
        _ -> Enum.find_value([:right, :down, :left, :up], &Layout.neighbor(layout, id, &1))
      end

    case partner do
      nil -> {:noreply, socket}
      other -> {:noreply, socket |> put_layout(Layout.swap(layout, id, other)) |> sync_url()}
    end
  end

  # Closing down to one tile leaves a workspace entered by tiling in place
  # for that page's own URL: it began from a full page, and it ends as one.
  # A page the account may not open stays in its tile, where the refusal is
  # readable.
  def handle_event("close-tile", %{"id" => id}, socket) do
    layout = Layout.close(socket.assigns.tree, id)

    socket =
      socket
      |> assign(:monocle, socket.assigns.monocle and Layout.count(layout) > 1)
      |> update(:titles, &Map.delete(&1, id))
      |> put_layout(layout)
      |> keep_focus()

    case {socket.assigns.in_place?, socket.assigns.tiles} do
      {true, [%{access: :ok, path: path}]} -> {:noreply, push_navigate(socket, to: path)}
      _ -> {:noreply, sync_url(socket)}
    end
  end

  # The tile follows the pattern of the page it shows now, so the choice is
  # made on a record the person can see rather than from a list of kinds.
  def handle_event("follow-tile", %{"id" => id}, socket) do
    with %{path: path} <- Layout.fetch_leaf(socket.assigns.tree, id),
         pattern when is_binary(pattern) <- follow_pattern(path) do
      {:noreply,
       socket |> put_layout(Layout.follow(socket.assigns.tree, id, pattern)) |> sync_url()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unfollow-tile", %{"id" => id}, socket) do
    {:noreply, socket |> put_layout(Layout.follow(socket.assigns.tree, id, nil)) |> sync_url()}
  end

  def handle_event("toggle-monocle", params, socket) do
    socket =
      case params do
        %{"id" => id} -> focus(socket, id)
        _ -> socket
      end

    monocle? = not socket.assigns.monocle and not is_nil(socket.assigns.focused)
    {:noreply, socket |> assign(:monocle, monocle?) |> derive()}
  end

  def handle_event("toggle-split", %{"id" => id}, socket) do
    {:noreply, socket |> put_layout(Layout.toggle_split(socket.assigns.tree, id)) |> sync_url()}
  end

  def handle_event("resize-split", %{"id" => id, "ratio" => ratio}, socket)
      when is_number(ratio) do
    {:noreply, socket |> put_layout(Layout.resize(socket.assigns.tree, id, ratio)) |> sync_url()}
  end

  def handle_event("nudge-split", %{"id" => id, "side" => side}, socket) do
    case side(side) do
      {:ok, side} ->
        {:noreply,
         socket |> put_layout(Layout.nudge(socket.assigns.tree, id, side)) |> sync_url()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("resize-step", %{"side" => side}, socket) do
    with {:ok, side} <- side(side),
         id when is_binary(id) <- socket.assigns.focused do
      {:noreply,
       socket |> put_layout(Layout.resize_step(socket.assigns.tree, id, side)) |> sync_url()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open-layout", %{"n" => n}, socket) when is_integer(n) do
    case Enum.at(socket.assigns.saved, n - 1) do
      %{"slug" => slug} when n >= 1 ->
        {:noreply, push_patch(socket, to: ~p"/workspace/#{slug}")}

      _ ->
        {:noreply, socket}
    end
  end

  # ------------------------------------------------------------------
  # The page picker
  # ------------------------------------------------------------------

  def handle_event("open-picker", params, socket) do
    {:noreply,
     assign(socket,
       picker_open?: true,
       picker_for: current_leaf(socket.assigns.tree, params["id"])
     )}
  end

  def handle_event("close-picker", _params, socket) do
    {:noreply, assign(socket, picker_open?: false, picker_for: nil)}
  end

  def handle_event("add-tile", %{"path" => path}, socket) do
    layout = socket.assigns.tree

    at =
      current_leaf(layout, socket.assigns.picker_for) ||
        current_leaf(layout, socket.assigns.focused)

    if Enum.any?(socket.assigns.pages, &(&1.route == path)) do
      {:noreply, socket |> tile_page(path, at) |> sync_url()}
    else
      {:noreply, socket}
    end
  end

  # ------------------------------------------------------------------
  # Saved layouts
  # ------------------------------------------------------------------

  def handle_event("open-layouts", _params, socket) do
    {:noreply, socket |> clear_flash() |> assign(:layouts_open?, true)}
  end

  def handle_event("close-layouts", _params, socket) do
    {:noreply, assign(socket, layouts_open?: false, pending_delete: nil)}
  end

  def handle_event("validate-layout", %{"layout" => params}, socket) do
    {:noreply, assign(socket, :save_form, to_form(params, as: :layout))}
  end

  def handle_event("save-layout", %{"layout" => %{"label" => label}}, socket) do
    case SavedLayouts.save(
           socket.assigns.settings_scope,
           label,
           Layout.encode(socket.assigns.tree)
         ) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Saved the layout “%{label}”.", label: entry["label"]))
         |> assign(layouts_open?: false, save_form: to_form(%{"label" => ""}, as: :layout))
         |> load_saved()
         |> push_patch(to: ~p"/workspace/#{entry["slug"]}")}

      {:error, :label} ->
        {:noreply,
         assign(
           socket,
           :save_form,
           to_form(%{"label" => label},
             as: :layout,
             errors: [label: {"Give the layout a name of up to 60 characters.", []}]
           )
         )}

      {:error, :tree} ->
        {:noreply,
         put_flash(socket, :error, gettext("Open at least one page before saving a layout."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("The layout could not be saved."))}
    end
  end

  def handle_event("update-layout", _params, %{assigns: %{slug: slug, shared?: false}} = socket)
      when is_binary(slug) do
    scope = socket.assigns.settings_scope

    with {:ok, entry} <- SavedLayouts.fetch(scope, slug),
         {:ok, entry} <-
           SavedLayouts.save(scope, entry["label"], Layout.encode(socket.assigns.tree)) do
      {:noreply,
       socket
       |> load_saved()
       |> put_flash(:success, gettext("Updated the layout “%{label}”.", label: entry["label"]))}
    else
      {:error, :tree} ->
        {:noreply,
         put_flash(socket, :error, gettext("Open at least one page before saving a layout."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("The layout could not be updated."))}
    end
  end

  def handle_event("update-layout", _params, socket), do: {:noreply, socket}

  def handle_event("copy-layout", %{"id" => slug}, socket) do
    with {:ok, entry} <-
           SharedLayouts.fetch_visible(
             socket.assigns.company_scope,
             slug,
             socket.assigns.role_codes
           ),
         {:ok, copy} <-
           SavedLayouts.save(
             socket.assigns.settings_scope,
             copy_label(socket.assigns.saved, entry["label"]),
             copy_tree(socket, entry)
           ) do
      {:noreply,
       socket
       |> load_saved()
       |> put_flash(:success, gettext("Copied the shared workspace to your layouts."))
       |> push_patch(to: ~p"/workspace/#{copy["slug"]}")}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("The shared workspace could not be copied."))}
    end
  end

  def handle_event("rename-layout", %{"id" => slug, "label" => label}, socket) do
    case SavedLayouts.rename(socket.assigns.settings_scope, slug, label) do
      {:ok, _entry} ->
        {:noreply, socket |> load_saved() |> put_flash(:success, gettext("Renamed the layout."))}

      {:error, :label} ->
        {:noreply, put_flash(socket, :error, gettext("A layout name is one to 60 characters."))}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, gettext("The layout could not be renamed."))}
    end
  end

  def handle_event("delete-layout", %{"id" => slug}, socket) do
    {:noreply, socket |> clear_flash() |> assign(:pending_delete, slug)}
  end

  def handle_event("cancel-delete-layout", _params, socket) do
    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("confirm-delete-layout", _params, %{assigns: %{pending_delete: slug}} = socket)
      when is_binary(slug) do
    case SavedLayouts.delete(socket.assigns.settings_scope, slug) do
      :ok ->
        socket =
          socket
          |> assign(:pending_delete, nil)
          |> load_saved()
          |> put_flash(:success, gettext("Deleted the layout."))

        if socket.assigns.slug == slug,
          do:
            {:noreply,
             push_patch(socket, to: ~p"/workspace?t=#{Layout.encode(socket.assigns.tree)}")},
          else: {:noreply, socket}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:pending_delete, nil)
         |> put_flash(:error, gettext("The layout could not be deleted."))}
    end
  end

  def handle_event("confirm-delete-layout", _params, socket), do: {:noreply, socket}

  def handle_event("set-default-layout", %{"id" => slug}, socket) do
    case SavedLayouts.set_default(socket.assigns.settings_scope, slug) do
      :ok ->
        {:noreply,
         socket
         |> load_saved()
         |> put_flash(:success, gettext("The workspace now opens with this layout."))}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, gettext("The default layout could not be set."))}
    end
  end

  def handle_event("clear-default-layout", _params, socket) do
    :ok = SavedLayouts.set_default(socket.assigns.settings_scope, nil)

    {:noreply,
     socket |> load_saved() |> put_flash(:success, gettext("The workspace now opens empty."))}
  end

  # ------------------------------------------------------------------
  # The follow channel
  # ------------------------------------------------------------------

  @impl true
  def handle_info({:workspace_joined}, socket) do
    publish_follows(socket, socket.assigns.follows)
    {:noreply, socket}
  end

  # A page announced a record. Every tile following a pattern of the module
  # that owns the record goes to that record's page, unless it is there.
  def handle_info({:workspace_fact, %{kind: kind, id: id} = fact}, socket)
      when is_map_key(fact, :kind) do
    if Workspace.fact?(fact),
      do: follow_fact(socket, kind, id),
      else: {:noreply, socket}
  end

  # This host's own broadcast, and anything else on the topic.
  def handle_info(_message, socket), do: {:noreply, socket}

  defp follow_fact(socket, kind, id) do
    {layout, moved} =
      socket.assigns.tree
      |> Layout.leaves()
      |> Enum.reduce({socket.assigns.tree, []}, fn
        %{follow: pattern} = leaf, {layout, moved} when is_binary(pattern) ->
          with {:ok, %{source: ^kind}} <- RouteContract.fetch_pattern(pattern),
               path when is_binary(path) <- fill_pattern(pattern, id),
               false <- same_page?(leaf.path, path) do
            {Layout.update_path(layout, leaf.id, path), [{leaf.id, path} | moved]}
          else
            _ -> {layout, moved}
          end

        _leaf, acc ->
          acc
      end)

    case moved do
      [] ->
        {:noreply, socket}

      moved ->
        socket =
          Enum.reduce(moved, socket, fn {tile_id, path}, socket ->
            socket
            |> update(:titles, &Map.delete(&1, tile_id))
            |> push_event("tile-navigate", %{
              id: tile_id,
              path: Workspace.frame_url(path, socket.assigns.token)
            })
          end)

        {:noreply, socket |> put_layout(layout) |> sync_url(replace: true)}
    end
  end

  # The module ids the tiles follow, told to every page in the workspace
  # when they change and to a page that joins.
  defp follow_kinds(layout) do
    layout
    |> Layout.follows()
    |> Enum.flat_map(fn pattern ->
      case RouteContract.fetch_pattern(pattern) do
        {:ok, %{source: source}} when is_binary(source) -> [source]
        _other -> []
      end
    end)
    |> Enum.uniq()
  end

  defp publish_follows(socket, kinds) do
    if connected?(socket) and is_binary(socket.assigns.topic),
      do: Workspace.broadcast(socket.assigns.topic, {:workspace_follows, kinds})
  end

  # The route pattern a tile at `path` may follow: its page's own pattern
  # when that names one record, such as `/companies/:id`.
  defp follow_pattern(path) do
    with {:ok, %{path: pattern}} <- RouteContract.fetch_route(path),
         true <- Layout.follow_pattern?(pattern) do
      pattern
    else
      _ -> nil
    end
  end

  defp fill_pattern(pattern, id) do
    segment = URI.encode(to_string(id), &URI.char_unreserved?/1)

    pattern
    |> String.split("/", trim: true)
    |> Enum.map_join("/", fn
      ":" <> _param -> segment
      literal -> literal
    end)
    |> then(&("/" <> &1))
  end

  defp same_page?(current, path), do: URI.parse(current).path == path

  # ------------------------------------------------------------------
  # State
  # ------------------------------------------------------------------

  defp put_layout(socket, %Layout{} = layout) do
    kinds = follow_kinds(layout)
    if kinds != socket.assigns.follows, do: publish_follows(socket, kinds)

    socket |> assign(:tree, layout) |> assign(:follows, kinds) |> derive()
  end

  defp current_leaf(layout, id) when is_binary(id) do
    if Layout.fetch_leaf(layout, id), do: id
  end

  defp current_leaf(_layout, _id), do: nil

  defp focus(socket, id) do
    case Layout.fetch_leaf(socket.assigns.tree, id) do
      nil -> socket
      _leaf -> socket |> assign(:focused, id) |> derive()
    end
  end

  # After the tree changes under the focus, focus stays where it can.
  defp keep_focus(socket) do
    leaves = Layout.leaves(socket.assigns.tree)
    focused = socket.assigns.focused

    focused =
      cond do
        Enum.any?(leaves, &(&1.id == focused)) -> focused
        leaves == [] -> nil
        true -> List.first(leaves).id
      end

    socket |> assign(:focused, focused) |> derive()
  end

  defp sync_url(socket, opts \\ []) do
    encoded = Layout.encode(socket.assigns.tree)
    socket = assign(socket, :encoded, encoded)
    address =
      if socket.assigns.shared?, do: {:shared, socket.assigns.slug}, else: socket.assigns.slug

    to = workspace_path(address, encoded, socket.assigns.in_place?)
    push_patch(socket, to: to, replace: Keyword.get(opts, :replace, false))
  end

  defp workspace_path(nil, "", _in_place?), do: ~p"/workspace"
  defp workspace_path(nil, encoded, true), do: ~p"/workspace?t=#{encoded}&inplace=1"
  defp workspace_path(nil, encoded, false), do: ~p"/workspace?t=#{encoded}"

  defp workspace_path({:shared, slug}, encoded, _in_place?),
    do: ~p"/workspace/shared/#{slug}?t=#{encoded}"

  defp workspace_path(slug, encoded, _in_place?), do: ~p"/workspace/#{slug}?t=#{encoded}"

  defp load_saved(socket) do
    scope = socket.assigns.settings_scope

    assign(socket,
      saved: SavedLayouts.list(scope),
      shared: SharedLayouts.visible(socket.assigns.company_scope, socket.assigns.role_codes),
      default_slug: SavedLayouts.default_slug(scope)
    )
  end

  # Everything the template reads is computed once per change here, so the
  # template holds no geometry.
  defp derive(socket) do
    %{
      tree: layout,
      focused: focused,
      titles: titles,
      current_scope: current_scope,
      monocle: monocle
    } =
      socket.assigns

    %{leaves: leaves, handles: handles} = Layout.rects(layout)

    tiles =
      for {leaf, rect} <- leaves do
        focused? = leaf.id == focused

        %{
          id: leaf.id,
          path: leaf.path,
          title: Map.get(titles, leaf.id) || leaf.path,
          place: if(monocle and focused?, do: @full_place, else: rect_place(rect)),
          focused?: focused?,
          access: access(current_scope, leaf.path),
          following?: is_binary(leaf.follow),
          on_follow: follow_command(leaf)
        }
      end

    # Tiles render in creation order, never tree order: a swap or move that
    # reordered the elements would make the browser move a frame in the
    # DOM, and a moved frame reloads its page. Position is `place` alone,
    # which the hook applies, because the host's Content-Security-Policy
    # allows no inline style attribute.
    tiles = Enum.sort_by(tiles, &tile_order/1)

    labels = Map.new(tiles, &{&1.id, &1.title})

    handles =
      for {split, rect} <- handles do
        %{
          id: split.id,
          direction: split.direction,
          place: handle_place(split, rect),
          # The rectangle the split divides, for the hook to turn a pointer
          # position back into a ratio while dragging.
          rect: Enum.map_join([rect.x, rect.y, rect.w, rect.h], " ", &Float.round(&1, 4)),
          label:
            gettext("Resize %{first} and %{second}",
              first: first_label(split.first, labels),
              second: first_label(split.second, labels)
            )
        }
      end

    assign(socket, tiles: tiles, handles: handles)
  end

  # Ids are `t<n>` with n increasing, so length-then-text is numeric order.
  defp tile_order(%{id: id}), do: {byte_size(id), id}

  # The menu entry: stop following, follow the page shown, or nothing for a
  # page that names no record.
  defp follow_command(%{id: id, follow: pattern}) when is_binary(pattern),
    do: JS.push("unfollow-tile", value: %{id: id})

  defp follow_command(%{id: id, path: path}) do
    if follow_pattern(path), do: JS.push("follow-tile", value: %{id: id})
  end

  defp first_label(%{type: :leaf, id: id}, labels), do: Map.get(labels, id, id)
  defp first_label(%{type: :split, first: first}, labels), do: first_label(first, labels)

  defp rect_place(%{x: x, y: y, w: w, h: h}) do
    "left: #{pct(x)}; top: #{pct(y)}; width: #{pct(w)}; height: #{pct(h)}"
  end

  defp handle_place(%{direction: :h, ratio: ratio}, %{x: x, y: y, w: w, h: h}) do
    "left: #{pct(x + w * ratio)}; top: #{pct(y)}; height: #{pct(h)}"
  end

  defp handle_place(%{direction: :v, ratio: ratio}, %{x: x, y: y, w: w, h: h}) do
    "left: #{pct(x)}; top: #{pct(y + h * ratio)}; width: #{pct(w)}"
  end

  defp pct(fraction), do: "#{Float.round(fraction * 100, 3)}%"

  # The same judgement `RouteAccess` makes at mount, made ahead of it.
  defp access(current_scope, path) do
    case RouteContract.fetch_route(path) do
      :error ->
        :unserved

      {:ok, route} ->
        if operator_allows?(current_scope, route) and capability_allows?(current_scope, route),
          do: :ok,
          else: :forbidden
    end
  end

  defp operator_allows?(%{scope: %Scope{} = scope}, %{operator: true}),
    do: Scope.platform_operator?(scope)

  defp operator_allows?(_current_scope, %{operator: operator}), do: not operator

  defp capability_allows?(_current_scope, %{capability: nil}), do: true

  defp capability_allows?(current_scope, %{capability: capability}),
    do: allowed?(current_scope, capability)

  # The pages the picker offers: every leaf of the navigation this account
  # sees, which is already limited to served routes, minus this page itself.
  defp pages(current_scope) do
    current_scope
    |> Nav.tree()
    |> flatten_nav([])
    |> Enum.reject(&(&1.route == "/workspace"))
  end

  defp flatten_nav(nodes, trail) do
    Enum.flat_map(nodes, fn %{item: item, children: children} ->
      own =
        if is_binary(item.route),
          do: [
            %{id: item.id, label: item.label, route: item.route, trail: Enum.join(trail, " › ")}
          ],
          else: []

      own ++ flatten_nav(children, trail ++ [item.label])
    end)
  end

  # A frame reports its own location. It is trusted only as far as the
  # route manifest goes: a relative path this deployment serves, never an
  # absolute URL, so a frame can only ever show a Bilimbi page.
  defp tile_path?(path), do: Layout.page_path?(path) and Nav.served?(URI.parse(path).path)

  defp workspace_page?(path) do
    case URI.parse(path).path do
      "/workspace" -> true
      "/workspace/" <> _ -> true
      _other -> false
    end
  end

  defp clean_title(title) when is_binary(title) do
    title = title |> String.replace_suffix(@title_suffix, "") |> String.trim()
    if title == "", do: nil, else: String.slice(title, 0, 80)
  end

  defp clean_title(_title), do: nil

  defp side(side) when is_binary(side), do: Map.fetch(@sides, side)
  defp side(_side), do: :error

  defp current_label(saved, slug) do
    case Enum.find(saved, &(&1["slug"] == slug)) do
      nil -> slug
      entry -> entry["label"]
    end
  end

  defp copy_tree(%{assigns: %{shared?: true, slug: slug, tree: tree}}, %{"slug" => slug}),
    do: Layout.encode(tree)

  defp copy_tree(_socket, entry), do: entry["tree"]

  defp copy_label(saved, label) do
    taken = MapSet.new(saved, & &1["label"])

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn n -> if n == 1, do: label, else: "#{String.slice(label, 0, 50)} #{n}" end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp settings_scope(current_scope) do
    Settings.Scope.user(
      current_user_id(current_scope),
      current_scope.user["company_id"],
      current_scope.scope.tenant.id
    )
  end

  defp company_scope(current_scope) do
    case current_scope.user["company_id"] do
      nil -> nil
      company_id -> Settings.Scope.company(company_id)
    end
  end

  defp role_codes(current_scope) do
    scope = current_scope.scope
    user_id = current_user_id(current_scope)
    first = Authz.list_principal_role_assignments(scope, :user, user_id, page_size: 100)

    entries =
      if first.total_pages > 1 do
        first.entries ++
          Enum.flat_map(2..first.total_pages, fn page ->
            Authz.list_principal_role_assignments(scope, :user, user_id,
              page: page,
              page_size: 100
            ).entries
          end)
      else
        first.entries
      end

    entries
    |> Enum.filter(&(&1.company_id in [nil, current_scope.user["company_id"]]))
    |> Enum.map(& &1.role_code)
  end
end
