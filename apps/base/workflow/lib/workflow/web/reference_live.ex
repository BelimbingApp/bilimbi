defmodule Bilimbi.Base.Workflow.Web.ReferenceLive do
  @moduledoc "A generic Workflow action and history adapter used as an integration reference."
  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.UI.ListColumns
  alias Bilimbi.Base.Workflow

  @capability "admin.reference.record.approve"
  @work_builtins [
    %{id: "label", label: "Work"},
    %{id: "status", label: "Status"}
  ]
  @history_builtins [
    %{id: "status", label: "Status"},
    %{id: "transitioned_at", label: "When", type: :datetime}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:work_columns, ListColumns.mount("workflow-reference-work-rows", @work_builtins))
      |> assign(
        :history_columns,
        ListColumns.mount("workflow-reference-history-rows", @history_builtins)
      )

    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 ->
        {:ok, load(socket, parsed)}

      _ ->
        {:ok, empty(socket, %{type: "reference.record", id: nil}, :invalid_subject)}
    end
  end

  @impl true
  def handle_event("execute", %{"action" => key} = params, socket) do
    if allowed?(socket.assigns.current_scope, @capability) do
      execute(socket, key, params["work_item_id"])
    else
      {:noreply, assign(socket, :failure, failure_copy(:missing_capability))}
    end
  end

  def handle_event("clear_failure", _params, socket) do
    {:noreply, assign(socket, :failure, nil)}
  end

  def handle_event("work_grid", params, socket) do
    case ListColumns.handle(socket.assigns.work_columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :work_columns, columns)}
      _other -> {:noreply, socket}
    end
  end

  def handle_event("history_grid", params, socket) do
    case ListColumns.handle(socket.assigns.history_columns, params) do
      {:update, columns} -> {:noreply, assign(socket, :history_columns, columns)}
      _other -> {:noreply, socket}
    end
  end

  defp execute(socket, key, raw_work_item_id) do
    case find_action(socket.assigns.actions, key, raw_work_item_id) do
      nil ->
        {:noreply, assign(socket, :failure, failure_copy(:stale_action))}

      action ->
        case Workflow.execute_action(
               socket.assigns.current_scope.scope,
               socket.assigns.subject,
               request(action, socket.assigns.subject_version)
             ) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> put_flash(:success, "Action completed.")
             |> load(socket.assigns.subject.id)}

          {:error, reason} ->
            {:noreply, assign(socket, :failure, failure_copy(reason))}
        end
    end
  end

  defp load(socket, id) do
    subject = %{type: "reference.record", id: id}
    scope = socket.assigns.current_scope.scope

    with {:ok, %{subject_version: version, actions: actions}} <-
           Workflow.available_actions(scope, subject),
         {:ok, %{entries: history}} <- Workflow.history(scope, subject),
         {:ok, work} <- Workflow.pending_work(scope, subject: subject) do
      socket
      |> assign(
        subject: subject,
        subject_version: version,
        actions: actions,
        history: history,
        work: work.entries,
        failure: nil
      )
      |> load_columns(work.entries, history)
    else
      {:error, reason} -> empty(socket, subject, reason)
    end
  end

  defp empty(socket, subject, reason) do
    socket
    |> assign(
      failure: failure_copy(reason),
      subject: subject,
      subject_version: nil,
      actions: [],
      history: [],
      work: []
    )
    |> load_columns([], [])
  end

  defp load_columns(socket, work, history) do
    socket
    |> assign(:work_columns, ListColumns.load(socket.assigns.work_columns, work, & &1.id))
    |> assign(:history_columns, ListColumns.load(socket.assigns.history_columns, history, & &1.id))
  end

  defp request(action, version) do
    request = %{
      action_key: action.key,
      idempotency_key: "reference:" <> Ecto.UUID.generate(),
      expected_subject_version: version,
      payload: %{}
    }

    if action.work_item_id do
      Map.merge(request, %{
        process_run_id: action.process_run_id,
        work_item_id: action.work_item_id,
        expected_work_version: action.work_version
      })
    else
      request
    end
  end

  defp find_action(actions, key, raw_work_item_id) do
    work_item_id =
      case Integer.parse(to_string(raw_work_item_id || "")) do
        {parsed, ""} when parsed > 0 -> parsed
        _ -> nil
      end

    Enum.find(actions, &(&1.key == key and &1.work_item_id == work_item_id))
  end

  defp failure_copy(:missing_capability), do: "Your role does not allow this action."
  defp failure_copy(:human_actor_required), do: "A signed-in person is required."
  defp failure_copy(:stale_action), do: "That action is no longer available. Refresh the page."
  defp failure_copy(:subject_not_found), do: "This record is not available."
  defp failure_copy(:invalid_subject), do: "This record address is not valid."

  defp failure_copy(reason)
       when reason in [
              :stale_subject,
              :stale_work,
              :subject_version_conflict,
              :work_version_conflict
            ],
       do: "This record changed. Refresh the page and try again."

  defp failure_copy(_reason),
    do: "Workflow could not complete the request. Refresh the page and review the record."
end
