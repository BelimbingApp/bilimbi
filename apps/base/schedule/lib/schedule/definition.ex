defmodule Bilimbi.Base.Schedule.Definition do
  @moduledoc "Validated immutable recurrence definition discovered from an installed module."

  @enforce_keys [
    :key,
    :name,
    :expression,
    :cron,
    :timezone,
    :owner,
    :task_name,
    :worker,
    :args,
    :overlap,
    :misfire
  ]
  defstruct @enforce_keys ++ [owner_route: nil]

  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          expression: String.t(),
          cron: Crontab.CronExpression.t(),
          timezone: String.t(),
          owner: String.t(),
          task_name: String.t(),
          worker: module(),
          args: map(),
          overlap: :allow | :forbid,
          misfire: :coalesce,
          owner_route: String.t() | nil
        }
end
