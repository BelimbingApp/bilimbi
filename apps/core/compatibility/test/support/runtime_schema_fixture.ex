defmodule Bilimbi.Core.Compatibility.RuntimeSchemaFixture do
  @moduledoc false

  use Application

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  @enabled "enabled"
  @environment_variable "BILIMBI_RUNTIME_SCHEMA_FIXTURE"
  @required_constraint "employee_types_system_company_check"

  @impl Application
  def start(_type, _args) do
    if System.get_env(@environment_variable) == @enabled do
      verify_required_schema!()
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  defp verify_required_schema! do
    case SQL.query!(
           Repo,
           "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = $1)",
           [@required_constraint]
         ).rows do
      [[true]] ->
        :ok

      [[false]] ->
        raise "required runtime schema is missing: #{@required_constraint}"
    end
  end
end
