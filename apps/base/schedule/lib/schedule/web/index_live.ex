defmodule Bilimbi.Base.Schedule.Web.IndexLive do
  @moduledoc """
  Installation-global Schedule operator board.

  Definitions remain immutable contributor facts. This adapter filters and
  paginates through the Schedule API, re-authorizes every command, and polls
  bounded operational evidence without treating absence as proof of health.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Schedule
  alias Bilimbi.Base.Schedule.RunPage
  alias Bilimbi.Base.Settings

  @execute "admin.system.schedule.execute"
  @manage "admin.system.schedule.manage"
  @poll_interval 5_000
  @tabs ~w(tasks history settings)
  @task_statuses ~w(disabled failed never paused running skipped succeeded unreviewed)
  @run_statuses ~w(failed running skipped succeeded)
  @task_sortable ~w(name next_due last_run)
  @run_sortable ~w(started_at name source status)
  @page_sizes [25, 50, 100]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Schedule")
      |> assign(:can_execute, allowed?(socket.assigns.current_scope, @execute))
      |> assign(:can_manage, allowed?(socket.assigns.current_scope, @manage))
      |> assign(:diagnostics, Schedule.diagnostics())
      |> assign(:task_count, 0)
      |> assign(:task_state, :available)
      |> assign(:run_state, :available)
      |> assign(:retention_days, retention_days())
      |> assign(:retention_form, retention_form(retention_days()))
      |> assign(:run_page, empty_run_page())
      |> stream_configure(:tasks, dom_id: &task_dom_id/1)
      |> stream_configure(:runs, dom_id: &run_dom_id/1)
      |> stream(:tasks, [])
      |> stream(:runs, [])

    if connected?(socket), do: Process.send_after(self(), :poll, @poll_interval)
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, state_from_params(params))}
  end

  @impl true
  def handle_event("filter_tasks", %{"task" => params}, socket) do
    state = %{
      socket.assigns.state
      | task_search: Map.get(params, "search", ""),
        task_status: task_status(Map.get(params, "status"))
    }

    {:noreply, push_state(socket, state)}
  end

  def handle_event("filter_tasks", _params, socket), do: {:noreply, socket}

  def handle_event("filter_runs", %{"run" => params}, socket) do
    state = %{
      socket.assigns.state
      | run_search: Map.get(params, "search", ""),
        run_status: run_status(Map.get(params, "status")),
        start_date: date_param(Map.get(params, "start_date")),
        end_date: date_param(Map.get(params, "end_date")),
        page_size: page_size(Map.get(params, "page_size"), socket.assigns.state.page_size),
        page: 1
    }

    {:noreply, push_state(socket, state)}
  end

  def handle_event("filter_runs", _params, socket), do: {:noreply, socket}

  def handle_event("sort_tasks", %{"sort" => column}, socket) when column in @task_sortable do
    state = socket.assigns.state
    sort_by = String.to_existing_atom(column)
    sort_dir = next_direction(state.task_sort_by, state.task_sort_dir, sort_by, :asc)
    {:noreply, push_state(socket, %{state | task_sort_by: sort_by, task_sort_dir: sort_dir})}
  end

  def handle_event("sort_tasks", _params, socket), do: {:noreply, socket}

  def handle_event("sort_runs", %{"sort" => column}, socket) when column in @run_sortable do
    state = socket.assigns.state
    sort_by = String.to_existing_atom(column)
    default = if sort_by == :started_at, do: :desc, else: :asc
    sort_dir = next_direction(state.run_sort_by, state.run_sort_dir, sort_by, default)

    {:noreply,
     push_state(socket, %{state | run_sort_by: sort_by, run_sort_dir: sort_dir, page: 1})}
  end

  def handle_event("sort_runs", _params, socket), do: {:noreply, socket}

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_state(socket, %{socket.assigns.state | page: positive_integer(page, 1)})}
  end

  def handle_event("run_now", %{"key" => key}, socket) do
    if allowed?(socket.assigns.current_scope, @execute) do
      command(socket, @execute, fn actor -> Schedule.run_now(actor, key) end, "Run queued.")
    else
      write_forbidden(socket)
    end
  end

  def handle_event("enable", %{"key" => key}, socket) do
    command(
      socket,
      @manage,
      fn actor -> Schedule.review_definition(actor, key, true) end,
      "Task enabled."
    )
  end

  def handle_event("disable", %{"key" => key}, socket) do
    command(
      socket,
      @manage,
      fn actor -> Schedule.review_definition(actor, key, false) end,
      "Task disabled."
    )
  end

  def handle_event("pause", %{"key" => key}, socket) do
    command(socket, @manage, fn actor -> Schedule.suppress(actor, key) end, "Task paused.")
  end

  def handle_event("resume", %{"key" => key}, socket) do
    command(socket, @manage, fn actor -> Schedule.resume(actor, key) end, "Task resumed.")
  end

  def handle_event("save_retention", %{"retention" => %{"days" => days}}, socket)
      when is_binary(days) do
    if allowed?(socket.assigns.current_scope, @manage) do
      case Integer.parse(days) do
        {value, ""} ->
          command(
            socket,
            @manage,
            fn actor -> Schedule.set_history_retention(actor, value) end,
            "Retention saved."
          )

        _invalid ->
          invalid_retention(socket)
      end
    else
      write_forbidden(socket)
    end
  end

  def handle_event("save_retention", _params, socket) do
    if allowed?(socket.assigns.current_scope, @manage) do
      invalid_retention(socket)
    else
      write_forbidden(socket)
    end
  end

  @impl true
  def handle_info(:poll, socket) do
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, load(socket, socket.assigns.state)}
  end

  def handle_info(:refresh, socket), do: {:noreply, load(socket, socket.assigns.state)}

  defp command(socket, capability, operation, success_message) do
    if authorized?(socket, capability) do
      case operation.(socket.assigns.current_scope.actor) do
        :ok ->
          {:noreply, socket |> load(socket.assigns.state) |> put_flash(:info, success_message)}

        {:ok, _result} ->
          {:noreply, socket |> load(socket.assigns.state) |> put_flash(:info, success_message)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error_message(reason))}
      end
    else
      write_forbidden(socket)
    end
  end

  defp invalid_retention(socket),
    do: {:noreply, put_flash(socket, :error, "Retention must be a whole number from 0 to 3650.")}

  defp write_forbidden(socket),
    do:
      {:noreply, put_flash(socket, :error, "You do not have permission to perform that action.")}

  defp authorized?(socket, capability) do
    case Authz.can(socket.assigns.current_scope.actor, capability) do
      %Decision{allowed: true} -> true
      %Decision{} -> false
    end
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end

  defp load(socket, state) do
    socket =
      socket
      |> assign(:state, state)
      |> assign(:task_form, task_form(state))
      |> assign(:run_form, run_form(state))
      |> assign(:can_execute, allowed?(socket.assigns.current_scope, @execute))
      |> assign(:can_manage, allowed?(socket.assigns.current_scope, @manage))
      |> assign(:diagnostics, Schedule.diagnostics())

    case state.tab do
      "tasks" -> load_tasks(socket, state)
      "history" -> load_runs(socket, state)
      "settings" -> assign_retention(socket)
    end
  end

  defp assign_retention(socket) do
    days = retention_days()
    socket |> assign(:retention_days, days) |> assign(:retention_form, retention_form(days))
  end

  defp load_tasks(socket, state) do
    case Schedule.list_tasks(
           search: state.task_search,
           status: nilify(state.task_status),
           sort_by: state.task_sort_by,
           sort_dir: state.task_sort_dir
         ) do
      {:ok, tasks} ->
        socket
        |> assign(:task_state, :available)
        |> assign(:task_count, length(tasks))
        |> stream(:tasks, tasks, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:task_state, :unavailable)
        |> assign(:task_count, 0)
        |> stream(:tasks, [], reset: true)
    end
  end

  defp load_runs(socket, state) do
    options = [
      search: state.run_search,
      status: nilify(state.run_status),
      start_date: state.start_date,
      end_date: state.end_date,
      sort_by: state.run_sort_by,
      sort_dir: state.run_sort_dir,
      page: state.page,
      page_size: state.page_size
    ]

    case Schedule.list_runs(options) do
      {:ok, %RunPage{} = page} when page.total_pages > 0 and page.page > page.total_pages ->
        load_runs(socket, %{state | page: page.total_pages})

      {:ok, %RunPage{} = page} ->
        socket
        |> assign(:state, state)
        |> assign(:run_state, :available)
        |> assign(:run_page, page)
        |> stream(:runs, page.entries, reset: true)

      {:error, reason} ->
        socket
        |> assign(
          :run_state,
          if(reason == :invalid_options, do: :invalid_filters, else: :unavailable)
        )
        |> assign(:run_page, empty_run_page(state.page_size))
        |> stream(:runs, [], reset: true)
    end
  end

  defp retention_days do
    case Settings.get("schedule.history.keep_days") do
      days when is_integer(days) and days in 0..3650 -> days
      _unknown -> :unavailable
    end
  rescue
    _error -> :unavailable
  catch
    :exit, _reason -> :unavailable
  end

  defp task_form(state) do
    to_form(%{"search" => state.task_search, "status" => state.task_status}, as: :task)
  end

  defp run_form(state) do
    to_form(
      %{
        "search" => state.run_search,
        "status" => state.run_status,
        "start_date" => date_string(state.start_date),
        "end_date" => date_string(state.end_date),
        "page_size" => state.page_size
      },
      as: :run
    )
  end

  defp retention_form(days),
    do: to_form(%{"days" => retention_value(days)}, as: :retention)

  defp state_from_params(params) do
    %{
      tab: tab(Map.get(params, "tab")),
      task_search: Map.get(params, "task_search", ""),
      task_status: task_status(Map.get(params, "task_status")),
      task_sort_by: task_sort(Map.get(params, "task_sort")),
      task_sort_dir: direction(Map.get(params, "task_dir"), :asc),
      run_search: Map.get(params, "run_search", ""),
      run_status: run_status(Map.get(params, "run_status")),
      start_date: date_param(Map.get(params, "start_date")),
      end_date: date_param(Map.get(params, "end_date")),
      run_sort_by: run_sort(Map.get(params, "run_sort")),
      run_sort_dir: direction(Map.get(params, "run_dir"), :desc),
      page: positive_integer(Map.get(params, "page"), 1),
      page_size: page_size(Map.get(params, "page_size"), 25)
    }
  end

  defp push_state(socket, state),
    do: push_patch(socket, to: ~p"/system/schedule?#{state_to_params(state)}")

  defp state_to_params(state) do
    %{
      "tab" => state.tab,
      "task_search" => state.task_search,
      "task_status" => state.task_status,
      "task_sort" => to_string(state.task_sort_by),
      "task_dir" => to_string(state.task_sort_dir),
      "run_search" => state.run_search,
      "run_status" => state.run_status,
      "start_date" => date_string(state.start_date),
      "end_date" => date_string(state.end_date),
      "run_sort" => to_string(state.run_sort_by),
      "run_dir" => to_string(state.run_sort_dir),
      "page" => state.page,
      "page_size" => state.page_size
    }
  end

  defp tab(value) when value in @tabs, do: value
  defp tab(_value), do: "tasks"
  defp task_status(value) when value in @task_statuses, do: value
  defp task_status(_value), do: ""
  defp run_status(value) when value in @run_statuses, do: value
  defp run_status(_value), do: ""
  defp task_sort(value) when value in @task_sortable, do: String.to_existing_atom(value)
  defp task_sort(_value), do: :next_due
  defp run_sort(value) when value in @run_sortable, do: String.to_existing_atom(value)
  defp run_sort(_value), do: :started_at
  defp direction("asc", _default), do: :asc
  defp direction("desc", _default), do: :desc
  defp direction(_value, default), do: default

  defp next_direction(current_field, current_direction, field, default) do
    cond do
      current_field != field -> default
      current_direction == :asc -> :desc
      true -> :asc
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp page_size(value, default) do
    parsed = positive_integer(value, default)
    if parsed in @page_sizes, do: parsed, else: default
  end

  defp date_param(nil), do: nil
  defp date_param(""), do: nil

  defp date_param(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date_param(_value), do: nil
  defp date_string(nil), do: ""
  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp nilify(""), do: nil
  defp nilify(value), do: value

  defp empty_run_page(page_size \\ 25) do
    %RunPage{entries: [], page: 1, page_size: page_size, total_entries: 0, total_pages: 0}
  end

  defp task_dom_id(task), do: "schedule-task-#{dom_key(task.key)}"
  defp run_dom_id(run), do: "schedule-run-#{run.id}"
  defp dom_key(key), do: String.replace(key, ~r/[^a-zA-Z0-9_-]/, "-")

  defp error_message(:audit_unavailable),
    do: "The action was not applied because audit evidence could not be recorded."

  defp error_message(:disabled), do: "Enable this definition before queuing it."
  defp error_message(:invalid_retention), do: "Retention must be a whole number from 0 to 3650."
  defp error_message(:not_found), do: "That schedule definition is no longer installed."
  defp error_message(:overlap), do: "This task already has an active occurrence."
  defp error_message(:suppressed), do: "Resume this task before queuing it."
  defp error_message(:unreviewed), do: "Review and enable this definition before queuing it."
  defp error_message(_reason), do: "Schedule state is unavailable; no action was confirmed."

  defp task_status_label(%{suppressed?: true}), do: "Paused"
  defp task_status_label(%{review_state: :unreviewed}), do: "Unreviewed"
  defp task_status_label(%{review_state: :disabled}), do: "Disabled"
  defp task_status_label(task), do: status_label(task.last_status)

  defp status_label(status), do: status |> to_string() |> String.capitalize()

  defp status_kind(status) when status in [:succeeded, "succeeded", :available, :none_due],
    do: :success

  defp status_kind(status) when status in [:failed, "failed", :unavailable, :due], do: :danger

  defp status_kind(status) when status in [:running, "running", :unreviewed, :unknown],
    do: :warning

  defp status_kind(_status), do: :neutral

  defp task_status_kind(%{suppressed?: true}), do: :warning
  defp task_status_kind(%{review_state: :unreviewed}), do: :warning
  defp task_status_kind(%{review_state: :disabled}), do: :neutral
  defp task_status_kind(task), do: status_kind(task.last_status)

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")

  defp format_datetime(%NaiveDateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")

  defp duration(nil), do: "—"
  defp duration(milliseconds) when milliseconds < 1_000, do: "#{milliseconds} ms"
  defp duration(milliseconds), do: "#{Float.round(milliseconds / 1_000, 1)} s"

  defp run_result(%{exit_code: exit_code}) when is_integer(exit_code), do: "Exit #{exit_code}"
  defp run_result(run), do: status_label(run.status)

  defp due_label(:none_due), do: "No work currently due"
  defp due_label(:due), do: "Work is due"
  defp due_label(:unknown), do: "Unknown"

  defp retention_value(:unavailable), do: ""
  defp retention_value(days), do: to_string(days)

  defp retention_label(0), do: "Keep all recorded runs"
  defp retention_label(1), do: "1 day"
  defp retention_label(days) when is_integer(days), do: "#{days} days"
  defp retention_label(:unavailable), do: "Unavailable"

  defp tab_path(state, tab) do
    params = state |> state_to_params() |> Map.put("tab", tab)
    ~p"/system/schedule?#{params}"
  end
end
