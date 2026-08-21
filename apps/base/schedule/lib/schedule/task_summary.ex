defmodule Bilimbi.Base.Schedule.TaskSummary do
  @moduledoc "Bounded operator-facing facts for one immutable schedule definition."

  @enforce_keys [
    :key,
    :name,
    :source,
    :owner,
    :expression,
    :timezone,
    :next_due_at,
    :review_state,
    :suppressed?,
    :overlap,
    :misfire,
    :last_status,
    :last_started_at,
    :last_finished_at,
    :last_runtime_ms
  ]
  defstruct @enforce_keys ++ [owner_route: nil]

  @type status :: :failed | :never | :running | :skipped | :succeeded | :unknown
  @type review_state :: :disabled | :enabled | :unreviewed
  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          source: String.t(),
          owner: String.t(),
          owner_route: String.t() | nil,
          expression: String.t(),
          timezone: String.t(),
          next_due_at: DateTime.t() | nil,
          review_state: review_state(),
          suppressed?: boolean(),
          overlap: :allow | :forbid,
          misfire: :coalesce,
          last_status: status(),
          last_started_at: NaiveDateTime.t() | nil,
          last_finished_at: NaiveDateTime.t() | nil,
          last_runtime_ms: non_neg_integer() | nil
        }
end
