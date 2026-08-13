defmodule Bilimbi.Core.Company.Migrations.AddAuthzRoleCompanyConstraints do
  use Ecto.Migration

  def up do
    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.base_authz_roles
    ADD CONSTRAINT base_authz_roles_company_foreign
    FOREIGN KEY (company_id) REFERENCES #{schema}.companies(id) ON DELETE RESTRICT
    """)

    execute("""
    ALTER TABLE #{schema}.base_authz_roles
    ADD CONSTRAINT base_authz_roles_custom_company_check
    CHECK (is_system = (company_id IS NULL))
    """)
  end

  def down do
    schema = quote_identifier(prefix() || "public")

    execute("""
    ALTER TABLE #{schema}.base_authz_roles
    DROP CONSTRAINT base_authz_roles_custom_company_check
    """)

    execute("""
    ALTER TABLE #{schema}.base_authz_roles
    DROP CONSTRAINT base_authz_roles_company_foreign
    """)
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
