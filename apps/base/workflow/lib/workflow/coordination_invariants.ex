defmodule Bilimbi.Base.Workflow.CoordinationInvariants do
  @moduledoc false
  alias Ecto.Adapters.SQL

  # Verification preserves unresolved runs and unknown/retired owner contracts.
  # Only contradictory durable ownership or corrupt graph facts fail adoption;
  # executable definition/state agreement is separately enforced at runtime.
  def errors(repo, prefix) do
    SQL.query!(
      repo,
      """
      SELECT 'run scope contradicts tenant identity', id
        FROM #{prefix}.base_workflow_process_runs
        WHERE (scope_type = 'tenant' AND tenant_id IS NULL)
           OR (scope_type = 'system' AND tenant_id IS NOT NULL)
      UNION ALL
      SELECT 'work tenant differs from run', w.id
        FROM #{prefix}.base_workflow_process_work_items w
        JOIN #{prefix}.base_workflow_process_runs r ON r.id = w.process_run_id
        WHERE w.tenant_id IS DISTINCT FROM r.tenant_id
      UNION ALL
      SELECT 'invalid work version or attempts', id
        FROM #{prefix}.base_workflow_process_work_items
        WHERE version < 1 OR attempts < 0 OR max_attempts < 1 OR delay_seconds < 0
      UNION ALL
      SELECT 'dependency crosses run or tenant', d.id
        FROM #{prefix}.base_workflow_process_dependencies d
        JOIN #{prefix}.base_workflow_process_work_items w ON w.id = d.work_item_id
        JOIN #{prefix}.base_workflow_process_work_items p ON p.id = d.depends_on_work_item_id
        WHERE w.process_run_id <> p.process_run_id OR w.id = p.id
           OR d.tenant_id IS DISTINCT FROM w.tenant_id OR d.tenant_id IS DISTINCT FROM p.tenant_id
      UNION ALL
      SELECT 'event crosses run or tenant', e.id
        FROM #{prefix}.base_workflow_process_events e
        JOIN #{prefix}.base_workflow_process_runs r ON r.id = e.process_run_id
        LEFT JOIN #{prefix}.base_workflow_process_work_items w ON w.id = e.work_item_id
        WHERE e.tenant_id IS DISTINCT FROM r.tenant_id
           OR (e.work_item_id IS NOT NULL AND (w.process_run_id <> r.id
               OR w.tenant_id IS DISTINCT FROM r.tenant_id))
           OR e.sequence < 1
      """,
      []
    ).rows
    |> Enum.map(fn [reason, id] -> "Workflow coordination #{reason} at id #{id}" end)
  end
end
