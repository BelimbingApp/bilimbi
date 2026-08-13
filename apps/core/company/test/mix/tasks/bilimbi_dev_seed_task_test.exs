defmodule Bilimbi.Core.Company.DevSeedTaskTest do
  use Bilimbi.Base.Database.DataCase, async: false

  import Bilimbi.Core.Company.TestFixtures

  alias Bilimbi.Core.Company

  setup do
    create_company_identity_tables!()

    previous_env = Mix.env()
    previous_shell = Mix.shell()

    Mix.env(:dev)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.env(previous_env)
      Mix.shell(previous_shell)
      Mix.Task.reenable("bilimbi.dev.seed")
    end)

    :ok
  end

  test "seeds the platform identity once and resolves it on rerun" do
    assert :ok = Mix.Task.run("bilimbi.dev.seed")
    assert_receive {:mix_shell, :info, [first_message]}
    assert first_message =~ ~r/tenant \d+ \(created\), company \d+ \(created\)/

    assert {:ok, company} = Company.platform_operator_company()
    assert company.code == "bilimbi_dev"
    assert company.name == "Bilimbi Development"

    Mix.Task.reenable("bilimbi.dev.seed")

    assert :ok = Mix.Task.run("bilimbi.dev.seed")
    assert_receive {:mix_shell, :info, [second_message]}
    assert second_message =~ ~r/tenant \d+ \(existing\), company \d+ \(existing\)/

    assert [[1]] =
             Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "SELECT count(*) FROM tenants", []).rows

    assert [[1]] =
             Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "SELECT count(*) FROM companies", []).rows
  end

  test "refuses to seed outside development" do
    Mix.env(:test)

    assert_raise Mix.Error, ~r/only run in the dev Mix environment/, fn ->
      Mix.Task.run("bilimbi.dev.seed")
    end
  end

  test "rejects arguments before starting the application" do
    assert_raise Mix.Error, ~r/accepts no arguments/, fn ->
      Mix.Task.run("bilimbi.dev.seed", ["unexpected"])
    end
  end
end
