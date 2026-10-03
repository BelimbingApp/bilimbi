defmodule Bilimbi.Base.Repo do
  use Ecto.Repo,
    otp_app: :bilimbi_base_database,
    adapter: Ecto.Adapters.Postgres

  alias Bilimbi.Base.Database.BulkCapture
  alias Bilimbi.Base.Database.WriteCapture

  # ADR 0013 (#630, #785): every successful write through this repo —
  # the eight struct functions and the three query-based bulk functions —
  # dispatches to the configured write capture, making the audit trail
  # comprehensive by default the way Belimbing's wildcard mutation
  # listener is. Belimbing's Eloquent model events do not fire for
  # query-builder writes; Bilimbi departs from the source there, because
  # parity is not a reason to leave a hole in an audit trail.
  #
  # Raw SQL still bypasses this seam and is kept empty of auditable writes
  # instead of covered: raw DML belongs only to the lifecycle modules
  # (seed ledger, compatibility cutover), a review convention (ADR 0013).
  defoverridable Ecto.Repo

  @doc "Runs a callback after the outer transaction commits, or immediately outside one."
  @spec after_commit((-> term())) :: :ok
  def after_commit(callback) when is_function(callback, 0) do
    if in_transaction?() do
      callbacks = Process.get({__MODULE__, :after_commit}, [])
      Process.put({__MODULE__, :after_commit}, [callback | callbacks])
    else
      callback.()
    end

    :ok
  end

  def transact(fun_or_multi, opts) do
    if in_transaction?() do
      super(fun_or_multi, opts)
    else
      Process.put({__MODULE__, :after_commit}, [])

      try do
        result = super(fun_or_multi, opts)
        callbacks = Process.delete({__MODULE__, :after_commit})

        case result do
          {:ok, _} -> Enum.each(Enum.reverse(callbacks), & &1.())
          _ -> :ok
        end

        result
      after
        Process.delete({__MODULE__, :after_commit})
      end
    end
  end

  def insert(struct, opts) do
    with {:ok, result} <- super(struct, opts) do
      WriteCapture.dispatch(:insert, struct, result)
      {:ok, result}
    end
  end

  def update(struct, opts) do
    with {:ok, result} <- super(struct, opts) do
      WriteCapture.dispatch(:update, struct, result)
      {:ok, result}
    end
  end

  def delete(struct, opts) do
    with {:ok, result} <- super(struct, opts) do
      WriteCapture.dispatch(:delete, struct, result)
      {:ok, result}
    end
  end

  def insert_or_update(changeset, opts) do
    action = if changeset_persisted?(changeset), do: :update, else: :insert

    with {:ok, result} <- super(changeset, opts) do
      WriteCapture.dispatch(action, changeset, result)
      {:ok, result}
    end
  end

  def insert!(struct, opts) do
    result = super(struct, opts)
    WriteCapture.dispatch(:insert, struct, result)
    result
  end

  def update!(struct, opts) do
    result = super(struct, opts)
    WriteCapture.dispatch(:update, struct, result)
    result
  end

  def delete!(struct, opts) do
    result = super(struct, opts)
    WriteCapture.dispatch(:delete, struct, result)
    result
  end

  def insert_or_update!(changeset, opts) do
    action = if changeset_persisted?(changeset), do: :update, else: :insert
    result = super(changeset, opts)
    WriteCapture.dispatch(action, changeset, result)
    result
  end

  # The bulk writes gather the rows they affected before dispatching them.
  # `BulkCapture` decides what that costs and hands back the result the
  # caller would have received without capture, so the added `select` and
  # `returning: true` never reach them.
  def insert_all(schema_or_source, entries, opts) do
    case BulkCapture.plan_insert(__MODULE__, schema_or_source, entries, opts) do
      :skip ->
        super(schema_or_source, entries, opts)

      plan ->
        result = super(schema_or_source, entries, BulkCapture.write_opts(plan, opts))
        BulkCapture.record(__MODULE__, :insert, plan, result)
        BulkCapture.caller_result(plan, result)
    end
  end

  def update_all(queryable, updates, opts) do
    case BulkCapture.plan_update(__MODULE__, queryable, opts) do
      :skip ->
        super(queryable, updates, opts)

      plan ->
        result = super(BulkCapture.write_queryable(plan), updates, opts)
        BulkCapture.record(__MODULE__, :update, plan, result)
        BulkCapture.caller_result(plan, result)
    end
  end

  def delete_all(queryable, opts) do
    case BulkCapture.plan_delete(__MODULE__, queryable, opts) do
      :skip ->
        super(queryable, opts)

      plan ->
        result = super(BulkCapture.write_queryable(plan), opts)
        BulkCapture.record(__MODULE__, :delete, plan, result)
        BulkCapture.caller_result(plan, result)
    end
  end

  defp changeset_persisted?(%Ecto.Changeset{data: %{__meta__: %{state: :loaded}}}), do: true
  defp changeset_persisted?(_changeset), do: false
end
