defmodule Bilimbi.Base.Session.Web.IndexLive do
  @moduledoc """
  Operational session list.

  Names the signed-in user. Belimbing's screen left-joins `users` and shows
  `user_name` (`resources/core/views/livewire/admin/system/sessions/index.blade.php:55`);
  a session row here carries only `user_id`, and Base cannot query Core.

  The name comes from `Bilimbi.Base.PrincipalDirectory`, the seam ADR 0011
  specifies — a declared Base-to-Base dependency, not a reflective call into
  Core. What each row shows, per the ruling on #285:

  - `user_id` is nil → `Guest`, matching Belimbing's `?? __('Guest')`
  - the user is in the actor's tenant → **their name**
  - the user is outside it → `User \#{id}`

  The third case is the reason this is not a join. `Core.User`'s provider
  resolves only inside the actor's scope, so a session belonging to another
  tenant returns no name and keeps its id rather than leaking one across the
  boundary.

  Sorting the user column uses `user_id`, not display names: resolving names is
  a scoped Base PrincipalDirectory concern after the payload-free Session page
  has been selected.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.PrincipalDirectory
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Session.Page

  @page_sizes [25, 50, 100, 300]
  @default_page_size 25
  @default_page 1
  @sortable %{
    "user_id" => :user_id,
    "ip_address" => :ip_address,
    "user_agent" => :user_agent,
    "last_activity" => :last_activity
  }
  @manage_cap "admin.system.session.manage"

  defmodule State do
    @moduledoc false
    defstruct search: nil,
              sort_by: :last_activity,
              sort_dir: :desc,
              page: 1,
              per_page: 25
  end

  @impl true
  def mount(_params, session, socket) do
    %{"current_user" => %{"session_id" => current_session_id}} = session

    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> assign(:current_session_id, current_session_id)
     |> assign(:page_sizes, @page_sizes)
     |> assign(:index_state, %State{})
     |> assign(:sessions_page, empty_page())
     |> assign(:user_names, %{})
     |> assign(:filters_form, to_form(filters_form_params(%State{}), as: :filters))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    state =
      socket.assigns.index_state
      |> Map.put(
        :search,
        normalize_search(Map.get(filters, "search", socket.assigns.index_state.search))
      )
      |> Map.put(
        :per_page,
        normalize_page_size(Map.get(filters, "perPage", socket.assigns.index_state.per_page))
      )
      |> Map.put(:page, @default_page)

    {:noreply, push_patch(socket, to: sessions_path(state))}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    {:noreply,
     push_patch(socket, to: sessions_path(next_sort(socket.assigns.index_state, sort_by)))}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    state = %{socket.assigns.index_state | page: normalize_page(page)}
    {:noreply, push_patch(socket, to: sessions_path(state))}
  end

  @impl true
  def handle_event("terminate", %{"id" => id}, socket) do
    if can_manage?(socket) do
      terminate_listed(socket, id)
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to terminate sessions.")}
    end
  end

  defp terminate_listed(socket, id) do
    case Session.terminate_session(id, socket.assigns.current_session_id) do
      {:ok, :terminated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session terminated.")
         |> load_page(socket.assigns.index_state)}

      {:ok, :not_found} ->
        {:noreply, load_page(socket, socket.assigns.index_state)}

      {:error, :current_session} ->
        {:noreply, put_flash(socket, :error, "You cannot terminate your current session.")}
    end
  end

  defp can_manage?(socket) do
    allowed?(socket.assigns.current_scope, @manage_cap)
  end

  defp load_page(socket, state) do
    page =
      Session.list_sessions_page(
        search: state.search,
        page: state.page,
        page_size: state.per_page,
        sort_by: state.sort_by,
        sort_dir: state.sort_dir
      )

    cond do
      page.total_pages > 0 and state.page > page.total_pages ->
        push_patch(socket, to: sessions_path(%{state | page: page.total_pages}))

      page.total_pages == 0 and state.page > @default_page ->
        push_patch(socket, to: sessions_path(%{state | page: @default_page}))

      true ->
        socket
        |> assign(:index_state, state)
        |> assign(:sessions_page, page)
        |> assign(:filters_form, to_form(filters_form_params(state), as: :filters))
        |> assign(:user_names, user_names(socket, page.entries))
        |> stream(:sessions, page.entries, reset: true)
    end
  end

  defp empty_page do
    %Page{
      entries: [],
      page: @default_page,
      page_size: @default_page_size,
      total_entries: 0,
      total_pages: 0
    }
  end

  # `rank/3` returns a caller-independent directory ranking this screen does
  # not need, so it is collapsed to a lookup. It is still the right entry point:
  # it owns provider resolution and the ceiling, and calling a provider directly
  # would bypass both.
  #
  # Only `{:ok, _}` is matched on purpose. The page is limited to
  # #{Enum.max(@page_sizes)} rows, so the candidate set cannot approach the directory's
  # ceiling; an error here is a defect, and handling it would be dead code
  # dressed as a fallback. #429's recovery turns a raise into a flash.
  defp user_names(socket, rows) do
    candidates =
      rows
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{:user, &1})

    if candidates == [] do
      %{}
    else
      {:ok, named} = PrincipalDirectory.rank(socket.assigns.current_scope.scope, candidates)

      Map.new(named, &{&1.id, &1.name})
    end
  end

  defp state_from_params(params) do
    sort_by = normalize_sort_by(params["sort"] || params["sort_by"])

    %State{
      search: normalize_search(params["search"] || params["q"]),
      sort_by: sort_by,
      sort_dir: normalize_sort_dir(params["dir"] || params["sort_dir"], sort_by),
      page: normalize_page(params["page"]),
      per_page:
        normalize_page_size(params["per_page"] || params["perPage"] || params["page_size"])
    }
  end

  defp normalize_search(nil), do: nil

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_search(_value), do: nil

  defp normalize_sort_by(nil), do: :last_activity

  defp normalize_sort_by(value) when is_binary(value) do
    Map.get(@sortable, String.downcase(String.trim(value)), :last_activity)
  end

  defp normalize_sort_by(_value), do: :last_activity

  defp normalize_sort_dir(nil, sort_by), do: default_direction(sort_by)

  defp normalize_sort_dir(value, sort_by) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "asc" -> :asc
      "desc" -> :desc
      _ -> default_direction(sort_by)
    end
  end

  defp normalize_sort_dir(_value, sort_by), do: default_direction(sort_by)

  defp default_direction(:last_activity), do: :desc
  defp default_direction(_sort_by), do: :asc

  defp normalize_page(value) do
    case positive_integer(value) do
      page when is_integer(page) -> page
      _ -> @default_page
    end
  end

  defp normalize_page_size(value) do
    case positive_integer(value) do
      size when size in @page_sizes -> size
      _ -> @default_page_size
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp next_sort(state, sort_key) do
    field = normalize_sort_by(sort_key)

    if state.sort_by == field do
      %{state | sort_dir: toggle_sort_dir(state.sort_dir), page: @default_page}
    else
      %{state | sort_by: field, sort_dir: default_direction(field), page: @default_page}
    end
  end

  defp toggle_sort_dir(:asc), do: :desc
  defp toggle_sort_dir(:desc), do: :asc

  defp filters_form_params(state) do
    %{
      "search" => state.search || "",
      "perPage" => to_string(state.per_page)
    }
  end

  defp sessions_path(state) do
    search_val = if state.search not in [nil, ""], do: state.search
    sort_val = if state.sort_by != :last_activity, do: to_string(state.sort_by)
    dir_val = if state.sort_dir != default_direction(state.sort_by), do: to_string(state.sort_dir)
    page_val = if state.page != @default_page, do: state.page
    per_page_val = if state.per_page != @default_page_size, do: state.per_page

    params =
      []
      |> maybe_put(:search, search_val)
      |> maybe_put(:sort, sort_val)
      |> maybe_put(:dir, dir_val)
      |> maybe_put(:page, page_val)
      |> maybe_put(:per_page, per_page_val)

    case params do
      [] -> ~p"/system/sessions"
      _ -> ~p"/system/sessions?#{params}"
    end
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: params ++ [{key, value}]

  defp user_label(%{user_id: nil}, _names), do: "Guest"

  defp user_label(%{user_id: id}, names) do
    Map.get(names, id, "User #{id}")
  end

  defp truncate_ua(nil), do: "—"

  defp truncate_ua(user_agent) when is_binary(user_agent) do
    if String.length(user_agent) > 80 do
      String.slice(user_agent, 0, 80) <> "..."
    else
      user_agent
    end
  end

  defp relative_activity(unix) when is_integer(unix) do
    delta = max(System.system_time(:second) - unix, 0)

    cond do
      delta < 60 -> "just now"
      delta < 3_600 -> ago(div(delta, 60), "minute")
      delta < 86_400 -> ago(div(delta, 3_600), "hour")
      true -> ago(div(delta, 86_400), "day")
    end
  end

  # Belimbing renders this column through Carbon's `diffForHumans()`
  # (`resources/core/views/livewire/admin/system/sessions/index.blade.php:58`),
  # which pluralises per unit. Interpolating a hard-coded "s" meant every
  # session last seen between 24 and 48 hours ago read "1 days ago" -- a full
  # day wide, not an edge case.
  defp ago(1, unit), do: "1 #{unit} ago"
  defp ago(count, unit), do: "#{count} #{unit}s ago"
end
