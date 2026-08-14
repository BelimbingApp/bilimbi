defmodule Bilimbi.Base.Authz.Web.DecisionLogsLive do
  @moduledoc """
  Authorization decisions, newest first.

  Ports Belimbing's `app/Base/Authz/Livewire/DecisionLogs/Index.php`. This is
  the screen people reach for when someone says "it says I can't", so the two
  things it must make easy are filtering to denials and reading why one
  happened — hence the result filter and `reason` beside every row.

  One deliberate difference from Belimbing: it joins `users` to show and sort
  by an actor's name. `DecisionLogSummary` carries `actor_type` and `actor_id`
  and no name, so this shows those. See #184 — I have not assumed that is an
  oversight, since the read model calls itself payload-safe.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz

  # Belimbing also sorts by actor name, which needs a join this read model does
  # not offer. The rest map one to one.
  @sortable ~w(occurred_at capability allowed reason resource actor_type actor_id)
  @results ~w(allowed denied)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Decision Logs")}
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
        result: result_from(Map.get(params, "result")),
        page: 1
    }

    {:noreply, push_state(socket, state)}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) when column in @sortable do
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

  # Belimbing defaults occurred_at to descending: a log read ascending starts
  # at the oldest decision, which is never what the reader wanted.
  defp default_direction(:occurred_at), do: :desc
  defp default_direction(_column), do: :asc

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/authz/decision-logs?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Authz.list_decision_logs(socket.assigns.current_scope.scope,
        search: nilify(state.search),
        allowed: allowed_filter(state.result),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    socket
    |> assign(:state, state)
    |> assign(:page, page)
    |> stream(:logs, page.entries, reset: true)
  end

  defp allowed_filter("allowed"), do: true
  defp allowed_filter("denied"), do: false
  defp allowed_filter(_result), do: nil

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      result: result_from(Map.get(params, "result")),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: if(Map.get(params, "sort_dir") == "asc", do: :asc, else: :desc),
      page: to_int(Map.get(params, "page"), 1),
      page_size: 25
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

  defp result_from(value) when value in @results, do: value
  defp result_from(_value), do: ""

  # A hand-edited URL reaches String.to_existing_atom, so anything unrecognised
  # falls back rather than raising.
  defp sort_by_from(value) when value in @sortable, do: String.to_existing_atom(value)
  defp sort_by_from(_value), do: :occurred_at

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

  defp sort_indicator(state, column) do
    cond do
      state.sort_by != column -> nil
      state.sort_dir == :asc -> "hero-chevron-up"
      true -> "hero-chevron-down"
    end
  end

  defp actor_label(%{actor_type: :agent}), do: "Employee"
  defp actor_label(%{actor_type: :user}), do: "User"
  defp actor_label(%{actor_type: other}), do: to_string(other)

  defp resource_label(%{resource_type: nil}), do: "—"
  defp resource_label(%{resource_type: type, resource_id: nil}), do: type
  defp resource_label(%{resource_type: type, resource_id: id}), do: "#{type} ##{id}"

  defp occurred_at(%{occurred_at: nil}), do: "—"
  defp occurred_at(%{occurred_at: at}), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S")
end
