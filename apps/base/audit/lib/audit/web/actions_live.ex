defmodule Bilimbi.Base.Audit.Web.ActionsLive do
  @moduledoc """
  LiveView for exploring tenant audit actions.

  Ports Belimbing's `app/Base/Audit/Livewire/AuditLog/Actions.php`.
  Provides bounded paginated inspection of actions, diagnostic filtering,
  result categorization, trace IDs, and action retention management.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  # `occurred_at` opens descending. `diagnostics` defaults to hidden.
  # The URL keeps this screen's `page_size` key; `<.pagination>` posts `perPage`.
  @list ListState.spec!(
          sortable: %{
            occurred_at: :desc,
            actor_type: :asc,
            event: :asc,
            url: :asc,
            trace_id: :asc
          },
          default_sort: :occurred_at,
          page_sizes: [25, 50, 100, 300],
          default_page_size: 25,
          page_size_param: "page_size",
          filters: [
            actor_type: {:one_of, ~w(user agent guest console scheduler queue system), ""},
            event_family: {:one_of, ~w(http auth console database queue domain), ""},
            result: {:one_of, ~w(failure retained), ""},
            diagnostics: {:one_of, ~w(hide show), "hide"}
          ]
        )
  @manage_cap "admin.audit.log.manage"
  @builtins [
    %{
      id: "occurred_at",
      label: "Occurred",
      type: :datetime,
      sort: "occurred_at",
      sort_id: "actions-sort-occurred_at"
    },
    %{
      id: "actor_type",
      label: "Actor",
      type: :string,
      sort: "actor_type",
      sort_id: "actions-sort-actor_type"
    },
    %{id: "event", label: "Action", type: :string, sort: "event", sort_id: "actions-sort-event"},
    %{id: "context", label: "Context", type: :string},
    %{id: "result", label: "Result", type: :string},
    %{
      id: "trace_id",
      label: "Trace",
      type: :string,
      sort: "trace_id",
      sort_id: "actions-sort-trace_id"
    },
    %{id: "retain", label: "Retain", type: :string, align: :right}
  ]

  @write_guard_opt_out ~w(grid)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Audit Actions")
     |> assign(can_manage: allowed?(socket.assigns.current_scope, @manage_cap))
     |> assign(:columns, ListColumns.mount("actions-table", @builtins))}
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

  # `can_manage` only shows the control. The write re-asks the manage
  # capability, so a grant removed after the page opened still refuses.
  @impl true
  def handle_event("toggle_retain", %{"id" => id_str}, socket) do
    id = Params.positive_integer(id_str, 0)

    case Audit.toggle_retained(socket.assigns.current_scope.scope, id) do
      {:ok, _updated_action} ->
        {:noreply, load(socket, socket.assigns.state)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> assign(:can_manage, allowed?(socket.assigns.current_scope, @manage_cap))
         |> put_flash(:error, "You do not have permission to manage audit logs.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update retention status.")}
    end
  end

  defp push_state(socket, state) do
    push_patch(socket, to: ~p"/audit/actions?#{ListState.to_params(state)}")
  end

  defp load(socket, state) do
    page =
      Audit.list_actions(socket.assigns.current_scope.scope,
        search: Params.blank_to_nil(state.search),
        actor_type: Params.blank_to_nil(state.filters.actor_type),
        event_family: Params.blank_to_nil(state.filters.event_family),
        result: Params.blank_to_nil(state.filters.result),
        diagnostics: state.filters.diagnostics,
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
      |> assign(:can_manage, allowed?(socket.assigns.current_scope, @manage_cap))
      |> stream(:actions, page.entries, reset: true)
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

    diagnostic = diagnostic_http?(url, route)

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

  # One row per console command, whatever became of it. The context column
  # carries the SQL as typed so the command a reader is looking for can be
  # found without opening the payload.
  defp action_presentation(%{event: "database_query." <> _ = event, payload: payload}) do
    payload = payload || %{}
    sql = Map.get(payload, "sql", "—")

    {result_text, variant} =
      case event do
        "database_query.executed" ->
          {"Succeeded · #{Map.get(payload, "row_count", "?")} rows", :success}

        "database_query.refused" ->
          {"Refused · #{humanize(Map.get(payload, "guard", "guard"))}", :danger}

        "database_query.failed" ->
          {"Failed", :danger}

        _other ->
          {"Recorded", :default}
      end

    %{
      source: "SQL console",
      summary: Map.get(payload, "name") || "Console command",
      context: sql,
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

  defp diagnostic_http?(url, route) do
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
    |> Enum.map_join(" ", &String.capitalize/1)
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
