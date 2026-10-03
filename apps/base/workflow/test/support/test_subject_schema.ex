defmodule Bilimbi.Base.Workflow.TestSubjectSchema do
  @moduledoc false
  use Ecto.Schema

  schema "workflow_test_subjects" do
    field :tenant_id, :id
    field :company_id, :id
    field :status, :string
    field :marker, :string
  end
end
