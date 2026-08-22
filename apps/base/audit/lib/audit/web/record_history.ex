defmodule Bilimbi.Base.Audit.Web.RecordHistory do
  @moduledoc """
  Header affordance for a single auditable record's recent mutation trail.
  """

  use Bilimbi.Base.UI, :live_component

  alias Bilimbi.Base.Audit

  @impl true
  def update(assigns, socket) do
    {:ok, entries} =
      Audit.list_subject_mutations(
        assigns.current_scope.scope,
        assigns.auditable_types,
        assigns.auditable_id
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:title, fn -> "Record History" end)
     |> assign(:entries, entries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative inline-block text-left">
      <details class="group">
        <summary
          id={"#{@id}-toggle"}
          class="inline-flex cursor-pointer list-none items-center justify-center gap-2 rounded-xl border border-line-strong bg-surface px-4 py-2 text-sm font-semibold text-ink shadow-sm transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-action/25 focus-visible:ring-offset-2 focus-visible:ring-offset-canvas [&::-webkit-details-marker]:hidden"
        >
          <.icon name="hero-clipboard-document-list" class="size-4" />
          <span>History</span>
        </summary>

        <div
          id={"#{@id}-panel"}
          class="absolute right-0 z-40 mt-2 w-[min(34rem,calc(100vw-2rem))] rounded-xl border border-line bg-surface p-3 text-left shadow-xl shadow-ink/[0.08]"
        >
          <div class="flex items-start justify-between gap-3 border-b border-line pb-2">
            <div>
              <h2 class="text-sm font-semibold text-ink">{@title}</h2>
              <p class="text-xs text-ink-muted">{history_count(@entries)}</p>
            </div>
          </div>

          <ol :if={@entries != []} class="mt-2 max-h-96 space-y-2 overflow-y-auto">
            <li
              :for={entry <- @entries}
              id={"#{@id}-entry-#{entry.id}"}
              class="rounded-lg border border-line bg-surface px-3 py-2"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <% {badge_kind, badge_label} = event_badge(entry.event) %>
                <.badge kind={badge_kind}>{badge_label}</.badge>
                <.datetime
                  id={"#{@id}-entry-#{entry.id}-occurred"}
                  value={entry.occurred_at}
                  class="text-xs text-ink-muted"
                />
              </div>

              <div class="mt-1 text-xs text-ink-muted">
                {actor_label(entry)}
              </div>

              <% field_diffs = diffs(entry) %>
              <div :if={field_diffs != []} class="mt-2 space-y-1">
                <div :for={diff <- field_diffs} class="grid grid-cols-[7rem_minmax(0,1fr)] gap-2 font-mono text-xs">
                  <span class="truncate font-semibold text-ink-muted">{diff.field}</span>
                  <span class="min-w-0 truncate text-ink">
                    <%= if diff.sensitive do %>
                      redacted
                    <% else %>
                      <span class="text-danger-ink">{diff.old}</span>
                      <span class="px-1 text-ink-muted">-></span>
                      <span class="text-success-ink">{diff.new}</span>
                    <% end %>
                  </span>
                </div>
              </div>
              <p :if={field_diffs == []} class="mt-2 text-xs italic text-ink-muted">
                No field changes recorded.
              </p>
            </li>
          </ol>

          <p :if={@entries == []} id={"#{@id}-empty"} class="mt-3 rounded-lg bg-surface-sunken px-3 py-6 text-center text-sm text-ink-muted">
            No record history found.
          </p>
        </div>
      </details>
    </div>
    """
  end

  defp history_count([]), do: "No recent mutations"
  defp history_count([_]), do: "1 recent mutation"
  defp history_count(entries), do: "#{length(entries)} recent mutations"

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

  defp actor_label(%{actor_type: type}) when is_binary(type), do: String.capitalize(type)
  defp actor_label(_entry), do: "-"

  defp event_badge("created"), do: {:success, "Created"}
  defp event_badge("deleted"), do: {:danger, "Deleted"}
  defp event_badge("updated"), do: {:neutral, "Updated"}
  defp event_badge(other), do: {:neutral, String.capitalize(to_string(other))}

  defp diffs(%{event: "created", new_values: new_vals}) when is_map(new_vals) do
    Enum.map(new_vals, fn {key, value} ->
      %{field: to_string(key), old: "-", new: format_value(value), sensitive: sensitive_key?(key)}
    end)
  end

  defp diffs(%{event: "deleted", old_values: old_vals}) when is_map(old_vals) do
    Enum.map(old_vals, fn {key, value} ->
      %{field: to_string(key), old: format_value(value), new: "-", sensitive: sensitive_key?(key)}
    end)
  end

  defp diffs(%{old_values: old_vals, new_values: new_vals}) do
    old_map = old_vals || %{}
    new_map = new_vals || %{}

    (Map.keys(old_map) ++ Map.keys(new_map))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.filter(&(Map.get(old_map, &1) != Map.get(new_map, &1)))
    |> Enum.map(fn key ->
      %{
        field: to_string(key),
        old: format_value(Map.get(old_map, key)),
        new: format_value(Map.get(new_map, key)),
        sensitive: sensitive_key?(key)
      }
    end)
  end

  defp format_value(nil), do: "-"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_number(value), do: to_string(value)

  defp format_value(value) when is_map(value) or is_list(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      _ -> inspect(value)
    end
  end

  defp format_value(value), do: inspect(value)

  defp sensitive_key?(key) when is_binary(key) do
    key
    |> String.downcase()
    |> String.contains?(["password", "secret", "token", "key", "hash"])
  end

  defp sensitive_key?(key), do: sensitive_key?(to_string(key))
end
