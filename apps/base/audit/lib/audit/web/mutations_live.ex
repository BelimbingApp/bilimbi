defmodule Bilimbi.Base.Audit.Web.MutationsLive do
  @moduledoc """
  LiveView for exploring tenant data mutations.

  Ports Belimbing's `app/Base/Audit/Livewire/AuditLog/Mutations.php`.
  Provides bounded paginated inspection of data changes, old/new diffs,
  actor roles, and trace correlation.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Page
  alias Bilimbi.Base.Audit.Web.MutationDiff

  import MutationDiff, only: [diff_value: 1]

  @sortable ~w(occurred_at actor_type event auditable_type trace_id)
  @events ~w(created updated deleted)
  @page_sizes [25, 50, 100, 300]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Data Mutations")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  # The toolbar inputs post top-level names; `<.pagination>`'s rows-per-page
  # select posts under `filters[perPage]`. Both funnel through this event, so a
  # key the posting form did not carry keeps its current value rather than
  # resetting to the default.
  def handle_event("filter", params, socket) do
    current = socket.assigns.state
    filters = Map.get(params, "filters", params)

    state = %{
      current
      | search: Map.get(filters, "search", current.search),
        event: filter_event(Map.get(filters, "event", current.event)),
        page_size: to_page_size(Map.get(filters, "perPage"), current.page_size),
        page: 1
    }

    {:noreply, push_state(socket, state)}
  end

  @impl true
  def handle_event("sort", %{"sort" => column}, socket) when column in @sortable do
    state = socket.assigns.state
    column_atom = String.to_existing_atom(column)

    direction =
      cond do
        state.sort_by != column_atom -> default_direction(column_atom)
        state.sort_dir == :asc -> :desc
        true -> :asc
      end

    {:noreply, push_state(socket, %{state | sort_by: column_atom, sort_dir: direction, page: 1})}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: to_int(page, 1)})}
  end

  defp default_direction(:occurred_at), do: :desc
  defp default_direction(_column), do: :asc

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/audit/mutations?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Audit.list_mutations(socket.assigns.current_scope.scope,
        search: nilify(state.search),
        event: nilify(state.event),
        sort_by: state.sort_by,
        sort_dir: state.sort_dir,
        page: state.page,
        page_size: state.page_size
      )

    if beyond_last_page?(page) do
      load(socket, %{state | page: page.total_pages})
    else
      socket
      |> assign(:state, state)
      |> assign(:page, page)
      |> assign(:filters_form, page_size_form(state))
      |> stream(:mutations, page.entries, reset: true)
    end
  end

  defp beyond_last_page?(%Page{total_pages: total, page: page}) do
    total > 0 and page > total
  end

  # `<.pagination>` reads its rows-per-page value from `filters[:perPage]`; the
  # URL keeps this screen's own `page_size` key.
  defp page_size_form(state) do
    to_form(
      %{
        "search" => state.search,
        "event" => state.event,
        "perPage" => Integer.to_string(state.page_size)
      },
      as: :filters
    )
  end

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      event: filter_event(Map.get(params, "event")),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: sort_dir_from(params),
      page: to_int(Map.get(params, "page"), 1),
      page_size: to_page_size(Map.get(params, "page_size"), 25)
    }
  end

  defp state_to_params(state) do
    %{
      "search" => state.search,
      "event" => state.event,
      "sort_by" => to_string(state.sort_by),
      "sort_dir" => to_string(state.sort_dir),
      "page" => to_string(state.page),
      "page_size" => to_string(state.page_size)
    }
  end

  defp filter_event(val) when val in @events, do: val
  defp filter_event(_), do: ""

  defp sort_by_from(val) when val in @sortable, do: String.to_existing_atom(val)
  defp sort_by_from(_), do: :occurred_at

  defp sort_dir_from(%{"sort_dir" => "asc"}), do: :asc
  defp sort_dir_from(%{"sort_dir" => "desc"}), do: :desc

  defp sort_dir_from(params),
    do: params |> Map.get("sort_by") |> sort_by_from() |> default_direction()

  defp to_int(nil, default), do: default

  defp to_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp to_int(val, _default) when is_integer(val) and val > 0, do: val
  defp to_int(_val, default), do: default

  defp to_page_size(val, default) do
    parsed = to_int(val, default)
    if parsed in @page_sizes, do: parsed, else: default
  end

  defp nilify(""), do: nil
  defp nilify(val), do: val

  defp actor_label(%{actor_type: "user", actor_id: id}) when is_integer(id) and id > 0,
    do: "User ##{id}"

  defp actor_label(%{actor_type: "agent", actor_id: id}) when is_integer(id) and id > 0,
    do: "Employee ##{id}"

  defp actor_label(%{actor_type: "guest"}), do: "Guest"
  defp actor_label(%{actor_type: "console"}), do: "Console"
  defp actor_label(%{actor_type: "scheduler"}), do: "Scheduler"
  defp actor_label(%{actor_type: "queue"}), do: "Queue"

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
