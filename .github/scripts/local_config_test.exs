ExUnit.start()
Code.require_file(Path.expand("../../mix/local_config.exs", __DIR__))

defmodule Bilimbi.LocalConfigTest do
  use ExUnit.Case, async: false
  alias Bilimbi.LocalConfig

  @variables ~w(DATABASE_URL PGUSER PGPASSWORD PGHOST PGPORT PGDATABASE BILIMBI_DEV_HOST PORT)

  setup do
    root =
      Path.expand("../../tmp/local-config-test-#{System.unique_integer([:positive])}", __DIR__)

    File.mkdir_p!(Path.join(root, ".local"))
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      File.rm_rf!(root)
    end)

    %{root: root, path: Path.join(root, ".local/config.json")}
  end

  test "missing file uses the development defaults", %{root: root} do
    config = LocalConfig.load(root)
    assert config == %{}
    assert LocalConfig.database_options(config)[:database] == "bilimbi_dev"
    assert LocalConfig.https_options(config) == %{host: "bilimbi.localhost", port: 4000}
  end

  test "saved database and HTTPS settings are applied", %{root: root, path: path} do
    write(path, %{
      "database" => %{
        "name" => "sbg_dev",
        "host" => "db.local",
        "port" => 5434,
        "username" => "developer",
        "password" => "fixture-secret"
      },
      "https" => %{"host" => "sbg.bilimbi.localhost", "port" => 4010}
    })

    config = LocalConfig.load(root)

    assert LocalConfig.database_options(config) == [
             username: "developer",
             password: "fixture-secret",
             hostname: "db.local",
             port: 5434,
             database: "sbg_dev"
           ]

    assert LocalConfig.https_options(config) == %{host: "sbg.bilimbi.localhost", port: 4010}
  end

  test "shell values override individual saved fields", %{root: root, path: path} do
    write(path, %{
      "database" => %{"name" => "saved", "password" => "saved-secret"},
      "https" => %{"host" => "saved.localhost", "port" => 4010}
    })

    System.put_env(%{
      "PGDATABASE" => "shell_db",
      "PGPASSWORD" => "shell-secret",
      "PGUSER" => "shell_user",
      "PGHOST" => "shell_host",
      "PGPORT" => "5435",
      "BILIMBI_DEV_HOST" => "shell.localhost",
      "PORT" => "4011"
    })

    config = LocalConfig.load(root)

    assert LocalConfig.database_options(config) == [
             username: "shell_user",
             password: "shell-secret",
             hostname: "shell_host",
             port: 5435,
             database: "shell_db"
           ]

    assert LocalConfig.https_options(config) == %{host: "shell.localhost", port: 4011}
  end

  test "DATABASE_URL wins over saved values and individual shell fields", %{
    root: root,
    path: path
  } do
    write(path, %{"database" => %{"name" => "saved"}})

    System.put_env(%{
      "DATABASE_URL" => "ecto://user:password@localhost/url_db",
      "PGDATABASE" => "shell_db"
    })

    assert LocalConfig.database_options(LocalConfig.load(root)) == [
             url: "ecto://user:password@localhost/url_db"
           ]
  end

  test "HTTPS allocation preserves database credentials and writes privately", %{
    root: root,
    path: path
  } do
    database = %{"name" => "saved", "password" => "fixture-secret"}
    write(path, %{"database" => database})
    LocalConfig.save_https!(root, "sbg.bilimbi.localhost", 4010)
    config = LocalConfig.load(root)
    assert config["database"] == database
    assert config["https"] == %{"root" => root, "host" => "sbg.bilimbi.localhost", "port" => 4010}
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert File.read!(path) =~ "\n  \"database\": {\n"
    assert File.read!(path) =~ "\n    \"name\": \"saved\""
  end

  test "legacy address migrates once and canonical settings win", %{root: root, path: path} do
    legacy = Path.join(root, ".local/https/instance.json")
    File.mkdir_p!(Path.dirname(legacy))
    write(legacy, %{"root" => root, "host" => "legacy.localhost", "port" => 4003})

    write(path, %{
      "database" => %{"name" => "sbg_dev"},
      "https" => %{"host" => "current.localhost"}
    })

    config = LocalConfig.load(root)
    assert config["database"]["name"] == "sbg_dev"
    assert config["https"] == %{"root" => root, "host" => "current.localhost", "port" => 4003}
    refute File.exists?(legacy)
    assert LocalConfig.load(root) == config
    assert File.read!(path) =~ "\"database\": {\n    \"name\": \"sbg_dev\"\n  }"
  end

  test "a copied legacy address fails without removing it", %{root: root} do
    legacy = Path.join(root, ".local/https/instance.json")
    File.mkdir_p!(Path.dirname(legacy))
    write(legacy, %{"root" => "/another/checkout", "host" => "legacy.localhost", "port" => 4003})
    assert_raise ArgumentError, ~r/another checkout/, fn -> LocalConfig.load(root) end
    assert File.exists?(legacy)
  end

  test "malformed JSON and unknown fields fail without displaying values", %{
    root: root,
    path: path
  } do
    File.write!(path, ~s({"password":"fixture-secret",))
    error = assert_raise ArgumentError, fn -> LocalConfig.load(root) end
    assert error.message =~ "malformed JSON"
    refute error.message =~ "fixture-secret"

    for config <- [
          %{"unknown" => "fixture-secret"},
          %{"database" => %{"dbname" => "fixture-secret"}},
          %{"https" => %{"scheme" => "fixture-secret"}}
        ] do
      write(path, config)
      error = assert_raise ArgumentError, fn -> LocalConfig.load(root) end
      assert error.message =~ "unknown field"
      refute error.message =~ "fixture-secret"
    end
  end

  test "non-object sections, invalid types and port limits fail", %{root: root, path: path} do
    for config <- [
          [],
          %{"database" => nil},
          %{"https" => []},
          %{"database" => %{"name" => ""}},
          %{"database" => %{"port" => "5433"}},
          %{"database" => %{"password" => false}},
          %{"database" => %{"port" => 0}},
          %{"https" => %{"port" => 65536}},
          %{"https" => %{"host" => "example.com"}},
          %{"https" => %{"host" => false}},
          %{"https" => %{"host" => "bad.localhost\n"}},
          %{"database" => %{"name" => "invalid\u0000name"}},
          %{"https" => %{"host" => String.duplicate("x", 64) <> ".localhost"}}
        ] do
      write(path, config)
      assert_raise ArgumentError, fn -> LocalConfig.load(root) end
    end
  end

  test "invalid shell ports and hostnames fail clearly" do
    for {key, value} <- [
          {"PORT", "4000x"},
          {"PORT", "80"},
          {"BILIMBI_DEV_HOST", "EXAMPLE.localhost"}
        ] do
      System.put_env(key, value)
      assert_raise ArgumentError, fn -> LocalConfig.https_options(%{}) end
      System.delete_env(key)
    end

    System.put_env("PGPORT", "invalid")
    assert_raise ArgumentError, ~r/PGPORT/, fn -> LocalConfig.database_options(%{}) end
  end

  defp write(path, config), do: File.write!(path, :json.encode(config))
end
