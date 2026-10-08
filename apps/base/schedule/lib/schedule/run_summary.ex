defmodule Bilimbi.Base.Schedule.RunSummary do
  @moduledoc "Redacted schedule history row without worker arguments or output."

  @enforce_keys [:id, :source, :trigger, :key, :name, :status, :started_at]
  defstruct @enforce_keys ++
              [
                :triggered_by_user_id,
                :triggered_by_name,
                :expression,
                :finished_at,
                :exit_code,
                :runtime_ms
              ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          source: String.t(),
          trigger: String.t(),
          triggered_by_user_id: pos_integer() | nil,
          triggered_by_name: String.t() | nil,
          key: String.t(),
          name: String.t(),
          expression: String.t() | nil,
          status: String.t(),
          started_at: NaiveDateTime.t(),
          finished_at: NaiveDateTime.t() | nil,
          exit_code: integer() | nil,
          runtime_ms: non_neg_integer() | nil
        }
end
