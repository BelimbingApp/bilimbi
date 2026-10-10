defmodule Bilimbi.Base.Audit.Web.MutationsLive do
  @moduledoc """
  LiveView for exploring tenant data mutations.

  Ports Belimbing's `app/Base/Audit/Livewire/AuditLog/Mutations.php`.
  Provides bounded paginated inspection of data changes, old/new diffs,
  actor roles, and trace correlation.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # `occurred_at` opens descending. The URL keeps this screen's `page_size`
  # key; `<.pagination>` still posts `perPage`.
  @list ListState.spec!(
          sortable: %{
            occurred_at: :desc,
            actor_type: :asc,
            event: :asc,
            auditable_type: :asc,
            trace_id: :asc
          },
          default_sort: :occurred_at,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "page_size",
          filters: [event: {:one_of, ~w(created updated deleted), ""}]
        )
  @builtins [
    %{
      id: "occurred_at",
      label: "Occurred",
      type: :datetime,
      sort: "occurred_at",
      sort_id: "mutations-sort-occurred_at"
    },
    %{
      id: "actor_type",
      label: "Actor",
      type: :string,
      sort: "actor_type",
      sort_id: "mutations-sort-actor_type"
    },
    %{id: "event", label: "Event", type: :string, sort: "event", sort_id: "mutations-sort-event"},
    %{
      id: "auditable_type",
      label: "Subject",
      type: :string,
      sort: "auditable_type",
      sort_id: "mutations-sort-auditable_type"
    },
    %{id: "details", label: "Details", type: :string},
    %{
      id: "trace_id",
      label: "Trace",
      type: :string,
      sort: "trace_id",
      sort_id: "mutations-sort-trace_id"
    }
  ]

  @write_guard_opt_out ~w(grid)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Data Mutations")
     |> assign(:columns, ListColumns.mount("mutations-table", @builtins))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, ListState.parse(params, @list))}
  end

  @impl true
  # The toolbar and `<.pagination>`'s rows-per-page select both post under
  # `filters` and funnel through this event, so a key the posting form did not
  # carry keeps its current value rather than resetting to the default.
  def handle_event("filter", params, socket) do
    {:noreply, push_state(socket, ListState.apply_filters(socket.assigns.state, filters(params)))}
  end

  @impl true
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
    push_patch(socket, to: ~p"/audit/mutations?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Audit.list_mutations(socket.assigns.current_scope.scope,
        search: Params.blank_to_nil(state.search),
        event: Params.blank_to_nil(state.filters.event),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    corrected = ListState.clamp_to_last_page(state, page)

    if corrected.page != state.page do
      load(socket, corrected)
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(:columns, ListColumns.load(socket.assigns.columns, page.entries, & &1.id))
      |> assign(:filters_form, ListState.filters_form(state))
      |> stream(:mutations, page.entries, reset: true)
    end
  end

  defp filters(params) when is_map(params), do: Map.get(params, "filters", %{})
  defp filters(_params), do: %{}

  defp actor_label(%{actor_type: "user", actor_id: id}) when is_integer(id) and id > 0,
    do: "User ##{id}"

  defp actor_label(%{actor_type: "agent", actor_id: id}) when is_integer(id) and id > 0,
    do: "Employee ##{id}"

  defp actor_label(%{actor_type: "guest"}), do: "Guest"
  defp actor_label(%{actor_type: "console"}), do: "Console"
  defp actor_label(%{actor_type: "scheduler"}), do: "Scheduler"
  defp actor_label(%{actor_type: "queue"}), do: "Queue"

  defp actor_label(%{actor_type: "system", system_principal: name}) when is_binary(name),
    do: "System · #{name}"

  defp actor_label(%{actor_type: type, actor_id: id}) when is_integer(id) and id > 0,
    do: "#{String.capitalize(type)} ##{id}"

  defp actor_label(%{actor_type: type}) when is_binary(type),
    do: String.capitalize(type)

  defp actor_label(_), do: "—"

  defp actor_subtext(%{impersonator_id: id} = row) when is_integer(id) and id > 0,
    do: "#{base_actor_subtext(row)} · impersonated by User ##{id}"

  defp actor_subtext(row), do: base_actor_subtext(row)

  defp base_actor_subtext(%{actor_role: role}) when is_binary(role) and role != "", do: role
  defp base_actor_subtext(%{actor_type: type}), do: to_string(type)

  defp event_badge("created"), do: {:success, "Created"}
  defp event_badge("updated"), do: {:info, "Updated"}
  defp event_badge("deleted"), do: {:danger, "Deleted"}
  defp event_badge(other), do: {:default, String.capitalize(to_string(other))}

  defp subject_label(%{subject_identifier: iden}) when is_binary(iden) and iden != "",
    do: iden

  defp subject_label(%{subject_name: name}) when is_binary(name) and name != "",
    do: name

  defp subject_label(%{auditable_type: type}) when is_binary(type),
    do: short_type(type)

  defp subject_label(_), do: "—"

  defp subject_subtext(%{auditable_type: type, auditable_id: id})
       when is_binary(type) and not is_nil(id),
       do: "#{short_type(type)} ##{id}"

  defp subject_subtext(%{auditable_type: type}) when is_binary(type),
    do: short_type(type)

  defp subject_subtext(_), do: ""

  defp short_type(type) do
    type
    |> to_string()
    |> String.split(["\\", "."])
    |> List.last()
  end
end
