defmodule Bilimbi.Base.Authz.Web.PrincipalCapabilitiesLive do
  @moduledoc """
  Capabilities granted or denied to a principal directly, bypassing roles.

  Ports Belimbing's `app/Base/Authz/Livewire/PrincipalCapabilities/Index.php`.
  These rows are the exceptions to the role model, so the question the screen
  has to answer quickly is "who has been given this outside their role, and was
  it a grant or a block".

  A direct **deny** outranks anything a role grants, which is why `allowed` is
  a filter and not just a column: the denials are the rows that explain
  otherwise baffling behaviour.

  Belimbing offers no principal-type filter and neither does this: the
  administration query accepts a principal filter only as a type *and* id
  together, so a type-only filter would raise. Sorting by principal type is
  supported and covers the same need.

  Belimbing joins users and companies to show names. Bilimbi resolves both
  halves through seams instead, because Base may not query Core. The company
  half uses the `CompanyDirectory` seam (#183): every row on the page is
  visibility-filtered to `company_ids/1`, so `Authz.companies_in_scope/1` can
  name each one. The principal half uses the `PrincipalDirectory` seam (#441,
  ADR 0011) — Core User answers for `user`, Core Employee for `agent`.

  Naming follows the hybrid #285 settled on: a principal inside the actor's
  tenant is named, one outside keeps its durable id, and nothing crosses the
  tenant boundary. Belimbing's own join is unscoped and names any user id it
  finds; that is the entropy this does not port. Decision-log actor names stay
  ids deliberately (#185 — an audit row is evidence of the moment, not a live
  view).

  Belimbing sorts on the joined `companies.name` and `users.name`. Both are
  ordered here with `array_position` over an id order resolved before
  pagination, so a page boundary never splits a name ordering without Base
  joining a Core table.

  Principal and Type are separate columns, as they are in Belimbing's blade,
  because they sort on different things: `principal_name` reads through the
  directory and `principal_type` is a column on the row. They were one column
  only while there was no name to put in it.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # Newest first, as Belimbing does: a direct capability is usually being read
  # because somebody just granted or revoked one. A URL that names a column
  # and no direction uses that column's default, so the link and the header
  # agree. The URL key is `per_page`.
  @list ListState.spec!(
          sortable: %{
            created_at: :desc,
            principal_type: :asc,
            principal_id: :asc,
            principal_name: :asc,
            capability: :asc,
            allowed: :asc,
            company_id: :asc,
            company_name: :asc
          },
          default_sort: :created_at,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "per_page",
          filters: [result: {:one_of, ~w(allowed denied), ""}]
        )

  @impl true
  def mount(_params, _session, socket) do
    # Resolved once here rather than inside `load/2`: the company set cannot
    # change while the page is open, and `load/2` runs on every search, filter,
    # sort and page change -- each of which was re-listing every company in the
    # tenant to render a column that never changes.
    companies = Authz.companies_in_scope(socket.assigns.current_scope.scope)

    {:ok,
     socket
     |> assign(:page_title, "Principal Capabilities")
     |> assign(:reach_caution?, reach_caution?(socket))
     |> assign(:company_names, Map.new(companies, &{&1.id, &1.name}))
     |> assign(:company_order, Enum.map(companies, & &1.id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, ListState.parse(params, @list))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_state(socket, ListState.apply_filters(socket.assigns.state, filters(params)))}
  end

  # The shared `<.table>` pushes the column as `phx-value-sort`, so the param is
  # "sort" rather than the "column" this screen used while it hand-rolled its
  # own header buttons.
  @impl true
  def handle_event("sort", %{"sort" => column}, socket) do
    state = socket.assigns.state

    case ListState.next_sort(state, column) do
      ^state -> {:noreply, socket}
      next -> {:noreply, push_state(socket, next)}
    end
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, ListState.put_page(socket.assigns.state, page))}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/principal-capabilities?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_principal_capabilities(socket.assigns.current_scope.scope,
        search: Params.blank_to_nil(state.search),
        allowed: allowed_filter(state.filters.result),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size,
        company_order: socket.assigns.company_order
      )

    # `Page.page` echoes what was asked for, so an out-of-range page comes back
    # empty with a real `total_pages`. Rendered as-is that is a dead end: no
    # rows, no empty-state text (the filters are not why it is empty), and no
    # pager, because the pager only appears when there is more than one page.
    # Land the reader on the last real page instead.
    corrected = ListState.clamp_to_last_page(state, page)

    if corrected.page != state.page do
      load(socket, corrected)
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(:filters_form, ListState.filters_form(state))
      |> stream(:grants, page.entries, reset: true)
    end
  end

  defp allowed_filter("allowed"), do: true
  defp allowed_filter("denied"), do: false
  defp allowed_filter(_result), do: nil

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}

  # principal_type is a :string column, not an Ecto.Enum -- matching atoms here
  # silently fell through to the raw value, so every row read "agent" instead
  # of "Employee". "agent" is the stored word; "Employee" is what it means.
  defp principal_label(%{principal_type: "agent"}), do: "Employee"
  defp principal_label(%{principal_type: "user"}), do: "User"
  defp principal_label(%{principal_type: other}), do: to_string(other)

  # The badge already says which kind this is, so the second half carries the
  # name when the directory resolved one and the durable id when it did not.
  # An unresolved principal is not an error and must not read like one.
  defp principal_identity(%{principal_name: name}) when is_binary(name) and name != "", do: name
  defp principal_identity(%{principal_id: id}), do: to_string(id)

  # `put_principal_capability/6` rejects an unknown key, so this cannot be
  # created through the API. It becomes reachable when a module that declared
  # a capability is uninstalled: its rows survive, the registry forgets the
  # key, and the grant silently stops matching. Nothing raises -- authorization
  # fails closed by design -- so this badge is the only place an operator can
  # see that a grant has quietly become inert.
  defp unknown_capability?(%{capability: capability}),
    do: not Authz.capability_known?(capability)

  # Extracted so the summary line stays one readable line, as the sibling Roles
  # and Decision Logs screens have it. Inline, the longer noun pushed the `if`
  # past the formatter's width and it came back as six wrapped lines.
  # The grants query is visibility-filtered to `company_ids/1`, and the
  # directory returns exactly that id set, so every row resolves. A company
  # archived between the two queries is not in the directory; its id is the
  # honest fallback, not a stale name.
  defp company_name(_names, nil), do: "—"

  defp company_name(names, company_id) do
    case Map.fetch(names, company_id) do
      {:ok, name} -> name
      :error -> to_string(company_id)
    end
  end

  # `Authz` widens this listing for the platform-operator scope to rows attached
  # to no company (`Administration.company_visibility/2`). The caution names that
  # widening where the list is read; it changes nothing about what is listed.
  defp reach_caution?(socket) do
    Scope.platform_operator?(socket.assigns.current_scope.scope)
  end
end
