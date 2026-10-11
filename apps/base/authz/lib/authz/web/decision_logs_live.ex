defmodule Bilimbi.Base.Authz.Web.DecisionLogsLive do
  @moduledoc """
  Authorization decisions, newest first.

  Ports Belimbing's `app/Base/Authz/Livewire/DecisionLogs/Index.php`. This is
  the screen people reach for when someone says "it says I can't", so the two
  things it must make easy are filtering to denials and reading why one
  happened — hence the result filter and `reason` beside every row.

  Delegation context is kept: an employee acts on behalf of a user, and the row
  shows `(as #<id>)` exactly as Belimbing's blade does. `DecisionLogSummary`
  already carries `acting_for_user_id`, so no naming seam is involved -- an
  audit row that hides who an action was really for is the wrong kind of terse.

  One deliberate difference from Belimbing: it joins `users` to show and sort
  by an actor's name. `DecisionLogSummary` carries `actor_type` and `actor_id`
  and no name, so this shows those. Settled in #185: the omission is the
  payload-safe Base/Core boundary, not an oversight.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # Belimbing also sorts by actor name, which needs a join this read model does
  # not offer. The rest map one to one.
  # Every entry here is reachable from a header button. `actor_id` was listed
  # and had no header, so it was accepted from a URL and offered nowhere --
  # configuration that looks like a feature. Belimbing sorts by actor *name*,
  # which needs a join this read model does not have (#185).
  # `occurred_at` opens descending: a log read ascending starts at the oldest
  # decision, which is never what the reader wanted. A URL that names a column
  # and no direction uses that same default. The URL key is `per_page`.
  @list ListState.spec!(
          sortable: %{
            occurred_at: :desc,
            capability: :asc,
            allowed: :asc,
            reason: :asc,
            resource: :asc,
            actor_type: :asc
          },
          default_sort: :occurred_at,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "per_page",
          filters: [result: {:one_of, ~w(allowed denied), ""}]
        )
  @builtins [
    %{
      id: "occurred_at",
      label: "When",
      type: :datetime,
      sort: "occurred_at",
      sort_id: "logs-sort-occurred_at"
    },
    %{
      id: "actor_type",
      label: "Actor",
      type: :string,
      sort: "actor_type",
      sort_id: "logs-sort-actor_type"
    },
    %{
      id: "capability",
      label: "Capability",
      type: :string,
      sort: "capability",
      sort_id: "logs-sort-capability"
    },
    %{
      id: "allowed",
      label: "Result",
      type: :string,
      sort: "allowed",
      sort_id: "logs-sort-allowed"
    },
    %{id: "reason", label: "Reason", type: :string, sort: "reason", sort_id: "logs-sort-reason"},
    %{
      id: "resource",
      label: "Resource",
      type: :string,
      sort: "resource",
      sort_id: "logs-sort-resource"
    }
  ]

  @write_guard_opt_out ~w(grid)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Decision Logs",
       reach_caution?: reach_caution?(socket),
       columns: ListColumns.mount("decision-logs", @builtins)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, ListState.parse(params, @list))}
  end

  @impl true
  # The toolbar and `<.pagination>`'s page-size select both post under
  # `filters` and funnel through this event. A key the form did not post
  # keeps its current value.
  def handle_event("filter", params, socket) do
    {:noreply, push_state(socket, ListState.apply_filters(socket.assigns.state, filters(params)))}
  end

  @impl true
  # The flexible table routes its sort operation through this event so the
  # page keeps its existing URL sort state.
  def handle_event("sort", %{"sort" => column}, socket) do
    state = socket.assigns.state

    case ListState.next_sort(state, column) do
      ^state -> {:noreply, socket}
      next -> {:noreply, push_state(socket, next)}
    end
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  def handle_event("grid", params, socket) do
    case ListColumns.handle(socket.assigns.columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :columns, columns)}
      {:sort, column} -> handle_event("sort", %{"sort" => column}, socket)
      :noop -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, ListState.put_page(socket.assigns.state, page))}
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/decision-logs?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_decision_logs(socket.assigns.current_scope.scope,
        search: Params.blank_to_nil(state.search),
        allowed: allowed_filter(state.filters.result),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
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
      |> assign(:columns, ListColumns.load(socket.assigns.columns, page.entries, & &1.id))
      |> assign(:filters_form, ListState.filters_form(state))
    end
  end

  defp allowed_filter("allowed"), do: true
  defp allowed_filter("denied"), do: false
  defp allowed_filter(_result), do: nil

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}

  defp actor_label(%{actor_type: "agent"}), do: "Employee"
  defp actor_label(%{actor_type: "user"}), do: "User"
  defp actor_label(%{actor_type: "system"}), do: "System"
  defp actor_label(%{actor_type: other}), do: to_string(other)

  defp resource_label(%{resource_type: nil}), do: "—"
  defp resource_label(%{resource_type: type, resource_id: nil}), do: type
  defp resource_label(%{resource_type: type, resource_id: id}), do: "#{type} ##{id}"

  # `Authz` widens this listing for the platform-operator scope to rows attached
  # to no company (`Administration.company_visibility/2`). The caution names that
  # widening where the list is read; it changes nothing about what is listed.
  defp reach_caution?(socket) do
    Scope.platform_operator?(socket.assigns.current_scope.scope)
  end
end
