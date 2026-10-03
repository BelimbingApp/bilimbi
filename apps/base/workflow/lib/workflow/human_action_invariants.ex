defmodule Bilimbi.Base.Workflow.HumanActionInvariants do
  @moduledoc false
  alias Ecto.Adapters.SQL

  # A retained request is either complete, with its saved result, or still
  # open with neither; a row that disagrees with itself cannot be replayed
  # truthfully. Hashes, legacy aliases and actor types are preserved as data.
  def errors(repo, prefix) do
    SQL.query!(
      repo,
      """
      SELECT 'human request completion and result disagree', id
        FROM #{prefix}.base_workflow_human_action_requests
        WHERE (completed_at IS NULL) <> (result IS NULL)
      """,
      []
    ).rows
    |> Enum.map(fn [reason, id] -> "Workflow #{reason} at id #{id}" end)
  end
end
