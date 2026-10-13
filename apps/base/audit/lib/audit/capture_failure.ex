defmodule Bilimbi.Base.Audit.CaptureFailure do
  @moduledoc false
  alias Bilimbi.Base.Audit.CaptureFailureSchema
  alias Bilimbi.Base.Repo

  # Only diagnostic identity is stored: exception messages can contain SQL values,
  # credentials, or entire changesets. Never serialize the error or failed row.
  def record(action, schema, error_type, context) do
    row =
      struct!(CaptureFailureSchema,
        action: to_string(action),
        schema_name: inspect(schema),
        error_type: inspect(error_type),
        actor_type: context.actor_type,
        actor_id: context.actor_id,
        impersonator_id: context.impersonator_id,
        system_principal: context.system_principal,
        company_id: context.company_id,
        tenant_id: context.tenant_id,
        trace_id: context.trace_id
      )

    opts = if Repo.in_transaction?(), do: [mode: :savepoint], else: []
    Repo.insert!(row, opts)
    :ok
  end
end
