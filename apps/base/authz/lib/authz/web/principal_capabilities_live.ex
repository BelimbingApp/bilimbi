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

  Belimbing joins users and companies to show names. The company half is
  resolved through the `CompanyDirectory` seam (#183): every row on the page is
  visibility-filtered to `company_ids/1`, so `Authz.companies_in_scope/1` can
  name each one without Base querying Core. The principal half stays id-based
  until #285 decides how Base may name a Core user or employee; decision-log
  actor names stay ids deliberately (#185 — an audit row is evidence of the
  moment, not a live view).

  Belimbing sorts on the joined `companies.name`. The LiveView passes the
  directory's id order (`company_order`) into the administration query, which
  orders with `array_position` so pagination stays correct without Base joining
  a Core table.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz

  @sortable ~w(created_at principal_type principal_id capability allowed company_id company_name)
  @results ~w(allowed denied)

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
     |> assign(:company_names, Map.new(companies, &{&1.id, &1.name}))
     |> assign(:company_order, Enum.map(companies, & &1.id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    state = %{
      socket.assigns.state
      | search: Map.get(params, "search", ""),
        result: member_or_blank(Map.get(params, "result"), @results),
        page: 1
    }

    {:noreply, push_state(socket, state)}
  end

  # The shared `<.table>` pushes the column as `phx-value-sort`, so the param is
  # "sort" rather than the "column" this screen used while it hand-rolled its
  # own header buttons.
  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    state = socket.assigns.state
    column = String.to_existing_atom(column)

    direction =
      cond do
        state.sort_by != column -> default_direction(column)
        state.sort_dir == :asc -> :desc
        true -> :asc
      end

    {:noreply, push_state(socket, %{state | sort_by: column, sort_dir: direction, page: 1})}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  # Newest first, as Belimbing does: a direct capability is usually being read
  # because somebody just granted or revoked one.
  defp default_direction(:created_at), do: :desc
  defp default_direction(_column), do: :asc

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/principal-capabilities?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_principal_capabilities(socket.assigns.current_scope.scope,
        search: nilify(state.search),
        allowed: allowed_filter(state.result),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: 25,
        company_order: socket.assigns.company_order
      )

    # `Page.page` echoes what was asked for, so an out-of-range page comes back
    # empty with a real `total_pages`. Rendered as-is that is a dead end: no
    # rows, no empty-state text (the filters are not why it is empty), and no
    # pager, because the pager only appears when there is more than one page.
    # Land the reader on the last real page instead.
    if beyond_last_page?(page) do
      load(socket, %{state | page: page.total_pages})
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> stream(:grants, page.entries, reset: true)
    end
  end

  defp beyond_last_page?(page),
    do: page.total_pages > 0 and page.page > page.total_pages

  defp allowed_filter("allowed"), do: true
  defp allowed_filter("denied"), do: false
  defp allowed_filter(_result), do: nil

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      result: member_or_blank(Map.get(params, "result"), @results),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: sort_dir_from(params),
      page: to_int(Map.get(params, "page"), 1)
    }
  end

  defp state_to_params(state) do
    %{
      "search" => state.search,
      "result" => state.result,
      "sort_by" => state.sort_by,
      "sort_dir" => state.sort_dir,
      "page" => state.page
    }
  end

  # Anything unrecognised becomes "no filter" rather than reaching
  # String.to_existing_atom, which a hand-edited URL would otherwise crash on.
  defp member_or_blank(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: ""
  end

  defp member_or_blank(_value, _allowed), do: ""

  defp sort_by_from(value) when value in @sortable, do: String.to_existing_atom(value)
  defp sort_by_from(_value), do: :created_at

  # A URL naming a column but no direction must mean what clicking that column
  # means. Defaulting everything to :desc made ?sort_by=capability render
  # descending while the header that produces it sorts ascending -- the same
  # link, two different pages.
  defp sort_dir_from(%{"sort_dir" => "asc"}), do: :asc
  defp sort_dir_from(%{"sort_dir" => "desc"}), do: :desc

  defp sort_dir_from(params),
    do: params |> Map.get("sort_by") |> sort_by_from() |> default_direction()

  defp to_int(nil, default), do: default

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp to_int(value, _default) when is_integer(value) and value > 0, do: value
  defp to_int(_value, default), do: default

  defp nilify(""), do: nil
  defp nilify(value), do: value

  # principal_type is a :string column, not an Ecto.Enum -- matching atoms here
  # silently fell through to the raw value, so every row read "agent" instead
  # of "Employee". "agent" is the stored word; "Employee" is what it means.
  defp principal_label(%{principal_type: "agent"}), do: "Employee"
  defp principal_label(%{principal_type: "user"}), do: "User"
  defp principal_label(%{principal_type: other}), do: to_string(other)

  defp created_at(%{created_at: nil}), do: "—"
  defp created_at(%{created_at: at}), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")

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
  defp grant_noun(1), do: "direct capability"
  defp grant_noun(_count), do: "direct capabilities"

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
end
