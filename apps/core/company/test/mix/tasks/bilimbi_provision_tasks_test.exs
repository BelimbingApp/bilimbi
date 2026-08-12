defmodule Bilimbi.Core.Company.ProvisionTasksTest do
  use Bilimbi.Base.Database.DataCase, async: false

  import Bilimbi.Core.Company.TestFixtures

  setup do
    create_company_identity_tables!()

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
      Mix.Task.reenable("bilimbi.platform.provision")
      Mix.Task.reenable("bilimbi.tenant.provision")
    end)

    :ok
  end

  test "platform command provisions once and resolves the existing identity on rerun" do
    arguments = [
      "--tenant-name",
      "Operator tenant",
      "--company-name",
      "Operator company",
      "--company-code",
      "operator_company"
    ]

    assert :ok = Mix.Task.run("bilimbi.platform.provision", arguments)
    assert_receive {:mix_shell, :info, [first_message]}
    assert first_message =~ "(created)"

    Mix.Task.reenable("bilimbi.platform.provision")

    assert :ok = Mix.Task.run("bilimbi.platform.provision", arguments)
    assert_receive {:mix_shell, :info, [second_message]}
    assert second_message =~ "(existing)"
  end

  test "tenant command atomically provisions a customer primary company" do
    assert :ok =
             Mix.Task.run("bilimbi.tenant.provision", [
               "--tenant-name",
               "Customer tenant",
               "--company-name",
               "Customer company",
               "--company-code",
               "customer_company"
             ])

    assert_receive {:mix_shell, :info, [message]}
    assert message =~ "Tenant ready"

    assert [[tenant_id, company_id]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               "SELECT tenant_id, company_id FROM tenant_primary_companies",
               []
             ).rows

    assert is_integer(tenant_id)
    assert is_integer(company_id)
  end

  test "tenant command rejects incomplete input before writing" do
    assert_raise Mix.Error, ~r/--company-code is required/, fn ->
      Mix.Task.run("bilimbi.tenant.provision", [
        "--tenant-name",
        "Customer tenant",
        "--company-name",
        "Customer company"
      ])
    end

    assert [[0]] =
             Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "SELECT count(*) FROM tenants", []).rows
  end
end
