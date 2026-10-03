defmodule Bilimbi.Base.Workflow.TestSubjectAdapter do
  @moduledoc false
  @behaviour Bilimbi.Base.Workflow.SubjectAdapter
  import Ecto.Query
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Base.Workflow.{Subject, TestSubjectSchema}

  @impl true
  def load(scope, id, mode) do
    query = from s in Tenancy.scope_query(TestSubjectSchema, scope), where: s.id == ^id
    query = if mode == :lock, do: from(s in query, lock: "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil ->
        {:error, :subject_not_found}

      row ->
        {:ok,
         %Subject{
           id: row.id,
           tenant_id: row.tenant_id,
           company_id: row.company_id,
           status: row.status,
           version: version(row),
           facts: %{"marker" => row.marker}
         }}
    end
  end

  # The whole row, as Belimbing hashed every raw attribute.
  defp version(row) do
    [row.id, row.tenant_id, row.company_id, row.status, row.marker]
    |> Enum.map_join("|", &inspect/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @impl true
  def authorize(_scope, %{facts: %{"marker" => "private"}}, _operation),
    do: {:error, :owner_refused}

  def authorize(_scope, _subject, _operation), do: :ok

  @impl true
  def persist(scope, subject, to, _context) do
    query =
      from s in Tenancy.scope_query(TestSubjectSchema, scope),
        where: s.id == ^subject.id and s.status == ^subject.status

    case Repo.update_all(query, set: [status: to]) do
      {1, _} -> :ok
      _ -> {:error, :stale_subject}
    end
  end
end
