defmodule Bilimbi.Base.Workflow.HumanActionHandler do
  @moduledoc """
  The owner's business effect of one human action, inside the gate's transaction.

  By the time `handle/4` runs, the gate has locked and proven the subject,
  checked the action's capability for the sealed Scope actor, settled
  idempotency (a repeated request never reaches the handler) and verified the
  expected subject version and, for work-bound actions, the work item's
  availability, executor and version. The handler receives the locked
  `Bilimbi.Base.Workflow.Subject`, the public action facts (`key`, `label`,
  `subject`, `capability`, `executor_key`) and the request facts
  (`action_key`, `idempotency_key`, `payload`, `process_run_id`,
  `work_item_id`).

  Return `{:ok, %{output: json, result_ref: text_or_nil}}`; `:outcome`
  defaults to `"completed"`. The output and result reference are saved on the
  request and, for a work-bound action, complete the work item in the same
  transaction. Any `{:error, reason}` rolls back the owner writes, the request
  row and the work completion together. Perform database effects only; take
  who acts from `Bilimbi.Base.Tenancy.Scope.actor/1`, never from the payload.
  """
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Workflow.Subject

  @callback handle(Scope.t(), Subject.t(), action :: map(), request :: map()) ::
              {:ok, map()} | {:error, term()}
end
