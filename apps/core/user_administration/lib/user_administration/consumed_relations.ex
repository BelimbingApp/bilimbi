defmodule Bilimbi.Core.UserAdministration.ConsumedRelations do
  @moduledoc false

  @contract_version 1
  @relations [
    %{
      owner: "core/user",
      contract: Bilimbi.Core.User.SchemaContract,
      migration_version: 20_260_813_094_500,
      relation: "users",
      columns: %{
        "id" => %{type: :bigint, nullable: false},
        "company_id" => %{type: :bigint, nullable: true},
        "name" => %{type: {:varchar, 255}, nullable: false},
        "email" => %{type: {:varchar, 255}, nullable: false},
        "created_at" => %{type: {:timestamp, 0}, nullable: true}
      }
    },
    %{
      owner: "core/company",
      contract: Bilimbi.Core.Company.SchemaContract,
      migration_version: 20_260_811_093_956,
      relation: "companies",
      columns: %{
        "id" => %{type: :bigint, nullable: false},
        "tenant_id" => %{type: :bigint, nullable: false},
        "name" => %{type: {:varchar, 255}, nullable: false},
        "deleted_at" => %{type: {:timestamp, 0}, nullable: true}
      }
    },
    %{
      owner: "base/authz",
      contract: Bilimbi.Base.Authz.SchemaContract,
      migration_version: 20_260_811_093_953,
      relation: "base_authz_principal_roles",
      columns: %{
        "company_id" => %{type: :bigint, nullable: true},
        "principal_type" => %{type: {:varchar, 40}, nullable: false},
        "principal_id" => %{type: :bigint, nullable: false},
        "role_id" => %{type: :bigint, nullable: false}
      }
    },
    %{
      owner: "base/authz",
      contract: Bilimbi.Base.Authz.SchemaContract,
      migration_version: 20_260_811_093_953,
      relation: "base_authz_roles",
      columns: %{
        "id" => %{type: :bigint, nullable: false},
        "company_id" => %{type: :bigint, nullable: true},
        "name" => %{type: {:varchar, 255}, nullable: false},
        "code" => %{type: {:varchar, 255}, nullable: false},
        "is_system" => %{type: :boolean, nullable: false}
      }
    }
  ]

  @spec contract_version() :: pos_integer()
  def contract_version, do: @contract_version

  @spec manifest() :: [map()]
  def manifest, do: @relations

  @spec verify!([map()]) :: :ok
  def verify!(relations \\ @relations) do
    Enum.each(relations, &verify_relation!/1)
    :ok
  end

  defp verify_relation!(entry) do
    actual = Enum.find(entry.contract.tables(), &(&1.name == entry.relation))

    actual_columns =
      if is_map(actual) do
        Map.new(entry.columns, fn {name, _expected} ->
          {name, actual.columns |> Map.get(name, %{}) |> Map.take([:type, :nullable])}
        end)
      end

    unless entry.contract.migration_version() == entry.migration_version and
             is_map(actual) and actual_columns == entry.columns do
      raise "consumed relation contract drift for #{entry.owner}:#{entry.relation} version #{@contract_version}"
    end
  end
end
