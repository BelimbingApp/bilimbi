defmodule Bilimbi.Base.Workflow.ProcessVersionSchema do
  @moduledoc false
  use Ecto.Schema

  schema "base_workflow_process_definition_versions" do
    field(:definition_key, :string)
    field(:definition_version, :integer)
    field(:definition_fingerprint, :string)
    field(:created_at, :naive_datetime)
    field(:updated_at, :naive_datetime)
  end
end
