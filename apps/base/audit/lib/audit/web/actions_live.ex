defmodule Bilimbi.Base.Audit.Web.ActionsLive do
  @moduledoc """
  LiveView for exploring tenant audit actions.

  Ports Belimbing's `app/Base/Audit/Livewire/AuditLog/Actions.php`.
  Provides bounded paginated inspection of actions, diagnostic filtering,
  result categorization, trace IDs, and action retention management.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Page

  @sortable ~w(occurred_at actor_type event url trace_id)
  @actor_types ~w(user agent guest console scheduler queue)
  @event_families ~w(http auth console queue domain)
  @results ~w(failure retained)
  @diagnostics ~w(hide show)
  @page_sizes [25, 50, 100, 300]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Audit Actions")}
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
        actor_type: filter_actor_type(Map.get(params, "actor_type")),
        event_family: filter_event_family(Map.get(params, "event_family")),
        result: filter_result(Map.get(params, "result")),
        diagnostics: filter_diagnostics(Map.get(params, "diagnostics")),
        page_size: to_page_size(Map.get(params, "page_size"), socket.assigns.state.page_size),
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

  @impl true
  def handle_event("toggle_retain", %{"id" => id_str}, socket) do
    id = to_int(id_str, 0)
    scope = socket.assigns.current_scope.scope

    case Audit.toggle_retained(scope, id) do
      {:ok, _updated_action} ->
        {:noreply, load(socket, socket.assigns.state)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update retention status.")}
    end
  end

  defp default_direction(:occurred_at), do: :desc
  defp default_direction(_column), do: :asc

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/audit/actions?#{state_to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Audit.list_actions(socket.assigns.current_scope.scope,
        search: nilify(state.search),
        actor_type: nilify(state.actor_type),
        event_family: nilify(state.event_family),
        result: nilify(state.result),
        diagnostics: state.diagnostics,
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
      |> stream(:actions, page.entries, reset: true)
    end
  end

  defp beyond_last_page?(%Page{total_pages: total, page: page}) do
    total > 0 and page > total
  end

  defp state_from_params(params) do
    %{
      search: Map.get(params, "search", ""),
      actor_type: filter_actor_type(Map.get(params, "actor_type")),
      event_family: filter_event_family(Map.get(params, "event_family")),
      result: filter_result(Map.get(params, "result")),
      diagnostics: filter_diagnostics(Map.get(params, "diagnostics")),
      sort_by: sort_by_from(Map.get(params, "sort_by")),
      sort_dir: sort_dir_from(params),
      page: to_int(Map.get(params, "page"), 1),
      page_size: to_page_size(Map.get(params, "page_size"), 25)
    }
  end

  defp state_to_params(state) do
    %{
      "search" => state.search,
      "actor_type" => state.actor_type,
      "event_family" => state.event_family,
      "result" => state.result,
      "diagnostics" => state.diagnostics,
      "sort_by" => to_string(state.sort_by),
      "sort_dir" => to_string(state.sort_dir),
      "page" => to_string(state.page),
      "page_size" => to_string(state.page_size)
    }
  end

  defp filter_actor_type(val) when val in @actor_types, do: val
  defp filter_actor_type(_), do: ""

  defp filter_event_family(val) when val in @event_families, do: val
  defp filter_event_family(_), do: ""

  defp filter_result(val) when val in @results, do: val
  defp filter_result(_), do: ""

  defp filter_diagnostics(val) when val in @diagnostics, do: val
  defp filter_diagnostics(_), do: "hide"

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

  defp occurred_at(%{occurred_at: nil}), do: "—"
  defp occurred_at(%{occurred_at: dt}), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")

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

  defp actor_subtext(%{actor_role: role}) when is_binary(role) and role != "", do: role
  defp actor_subtext(%{actor_type: type}), do: to_string(type)

  defp action_presentation(%{event: "http.request", url: url, payload: payload}) do
    payload = payload || %{}
    method = Map.get(payload, "method", "HTTP") |> to_string() |> String.upcase()
    route = Map.get(payload, "route")
    status = to_int_or_nil(Map.get(payload, "status"))
    duration = Map.get(payload, "duration_ms")
    path = path_from_url(url)

    display_route =
      cond do
        route == "default-livewire.update" -> "Livewire update"
        is_binary(route) and route != "" -> route
        is_binary(path) and path != "" -> path
        true -> "Request"
      end

    result_text =
      cond do
        status != nil and duration != nil -> "#{status} · #{round_num(duration)} ms"
        status != nil -> "#{status}"
        true -> "Completed"
      end

    variant =
      cond do
        is_nil(status) -> :default
        status >= 500 -> :danger
        status >= 400 -> :warning
        status >= 300 -> :info
        true -> :success
      end

    diagnostic = is_diagnostic_http?(url, route)

    %{
      source: "HTTP",
      summary: "#{method} #{display_route}",
      context: path || url || "—",
      result: result_text,
      variant: variant,
      diagnostic: diagnostic
    }
  end

  defp action_presentation(%{event: "console.command", payload: payload}) do
    payload = payload || %{}
    command = Map.get(payload, "command", "mix command")
    exit_code = to_int_or_nil(Map.get(payload, "exit_code"))

    result_text =
      if exit_code != nil, do: "Exit #{exit_code}", else: "Completed"

    variant = if exit_code in [nil, 0], do: :success, else: :danger

    %{
      source: "Console",
      summary: "#{command}",
      context: "CLI",
      result: result_text,
      variant: variant,
      diagnostic: false
    }
  end

  defp action_presentation(%{event: event, payload: payload})
       when is_binary(event) do
    payload = payload || %{}

    cond do
      String.starts_with?(event, "auth.") ->
        auth_presentation(event, payload)

      String.starts_with?(event, "queue.job.") ->
        job = Map.get(payload, "job", "Job")
        failed = event == "queue.job.failed"

        %{
          source: "Queue",
          summary: to_string(job),
          context: Map.get(payload, "queue", "default"),
          result: if(failed, do: "Failed", else: "Processed"),
          variant: if(failed, do: :danger, else: :success),
          diagnostic: false
        }

      String.starts_with?(event, "domain.") ->
        status = Map.get(payload, "status", "Recorded") |> to_string()
        action_name = String.replace_prefix(event, "domain.", "") |> humanize()
        failed = String.contains?(String.downcase(status), "fail")

        %{
          source: "Domain",
          summary: "Domain #{action_name}",
          context: Map.get(payload, "domain", "—"),
          result: status,
          variant: if(failed, do: :danger, else: :success),
          diagnostic: false
        }

      true ->
        %{
          source: "System",
          summary: humanize(event),
          context: "—",
          result: "Recorded",
          variant: :default,
          diagnostic: false
        }
    end
  end

  defp action_presentation(_) do
    %{
      source: "System",
      summary: "Action",
      context: "—",
      result: "Recorded",
      variant: :default,
      diagnostic: false
    }
  end

  defp auth_presentation("auth.login", _payload) do
    %{
      source: "Auth",
      summary: "Login",
      context: "—",
      result: "Succeeded",
      variant: :success,
      diagnostic: false
    }
  end

  defp auth_presentation("auth.logout", _payload) do
    %{
      source: "Auth",
      summary: "Logout",
      context: "—",
      result: "Completed",
      variant: :default,
      diagnostic: false
    }
  end

  defp auth_presentation("auth.login.failed", payload) do
    email = Map.get(payload, "email", "—")

    %{
      source: "Auth",
      summary: "Failed login",
      context: email,
      result: "Failed",
      variant: :danger,
      diagnostic: false
    }
  end

  defp auth_presentation(event, payload) do
    email = Map.get(payload, "email")

    %{
      source: "Auth",
      summary: humanize(event),
      context: email || "—",
      result: "Recorded",
      variant: :default,
      diagnostic: false
    }
  end

  defp is_diagnostic_http?(url, route) do
    url_str = to_string(url || "")
    route_str = to_string(route || "")

    route_str in ["default-livewire.update", "ai.chat.turn.events", "media.assets.stream"] or
      String.contains?(url_str, ["/livewire", "/api/ai/chat/turns/", "/media/assets/"])
  end

  defp path_from_url(nil), do: nil
  defp path_from_url(""), do: nil

  defp path_from_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) and path != "" -> path
      _ -> url
    end
  end

  defp humanize(str) when is_binary(str) do
    str
    |> String.split([".", "_", "-"])
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize(other), do: to_string(other)

  defp to_int_or_nil(nil), do: nil
  defp to_int_or_nil(val) when is_integer(val), do: val

  defp to_int_or_nil(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_int_or_nil(_), do: nil

  defp round_num(num) when is_float(num), do: round(num)
  defp round_num(num) when is_integer(num), do: num
  defp round_num(num) when is_binary(num), do: num
  defp round_num(_), do: 0
end
