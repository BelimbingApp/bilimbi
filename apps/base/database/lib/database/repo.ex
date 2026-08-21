defmodule Bilimbi.Base.Repo do
  use Ecto.Repo,
    otp_app: :bilimbi_base_database,
    adapter: Ecto.Adapters.Postgres

  alias Bilimbi.Base.Database.WriteCapture

  # ADR 0013 (#630): every successful struct write dispatches to the
  # configured write capture, making the audit trail comprehensive by
  # default the way Belimbing's wildcard mutation listener is. Query-based
  # bulk writes (`*_all`) and raw SQL are deliberately not captured —
  # Eloquent model events do not fire for query-builder writes either.
  defoverridable Ecto.Repo

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

  defp changeset_persisted?(%Ecto.Changeset{data: %{__meta__: %{state: :loaded}}}), do: true
  defp changeset_persisted?(_changeset), do: false
end
