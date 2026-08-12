defmodule Bilimbi.Base.Database.ProductionSeedTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ProductionSeed

  test "derives durable identity and order from installed module metadata" do
    seed =
      Database.production_seed!(:bilimbi_base_database, "reference/bootstrap", fn _repo -> :ok end)

    descriptor = Application.fetch_env!(:bilimbi_base_database, :bilimbi_module)

    assert seed.id == "base/database/reference/bootstrap"
    assert seed.module_id == descriptor.id
    assert seed.module_order == descriptor.order
  end

  test "rejects unstable identities and malformed callbacks" do
    assert_raise ArgumentError, ~r/local ID is invalid/, fn ->
      Database.production_seed!(:bilimbi_base_database, "Elixir.Module", fn _repo -> :ok end)
    end

    assert_raise ArgumentError, ~r/callback must be/, fn ->
      ProductionSeed.new!(
        id: "base/database/invalid-callback",
        module_id: "base/database",
        module_order: 0,
        callback: :not_callable
      )
    end
  end

  test "resolves an explicit provider whose module atom is not loaded yet" do
    elixir = System.find_executable("elixir")
    elixirc = System.find_executable("elixirc")

    assert elixir
    assert elixirc

    fixture_dir =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-unloaded-provider-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(fixture_dir)

    on_exit(fn -> File.rm_rf!(fixture_dir) end)

    source_path = Path.join(fixture_dir, "unloaded_provider.ex")

    File.write!(source_path, """
    defmodule Bilimbi.Base.Database.UnloadedProviderFixture do
    end
    """)

    assert {_, 0} =
             System.cmd(elixirc, ["-o", fixture_dir, source_path], stderr_to_stdout: true)

    assert File.exists?(
             Path.join(fixture_dir, "Elixir.Bilimbi.Base.Database.UnloadedProviderFixture.beam")
           )

    script =
      ~s|Code.prepend_path(Base.decode64!("#{Base.encode64(fixture_dir)}")); provider = Mix.Tasks.Bilimbi.Seeds.Run.provider_module!("Bilimbi.Base.Database.UnloadedProviderFixture"); IO.puts(Atom.to_string(provider))|

    assert {output, 0} =
             System.cmd(
               elixir,
               [
                 "--erl",
                 "-noinput",
                 "-pa",
                 Mix.Project.compile_path(),
                 "-pa",
                 fixture_dir,
                 "-e",
                 script
               ],
               stderr_to_stdout: true
             )

    assert output =~ "Elixir.Bilimbi.Base.Database.UnloadedProviderFixture"
  end
end
