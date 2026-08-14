defmodule Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnosticsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnostics, as: Diagnostics

  @safe_nested_output "nested command failed safely"

  test "captures the original assertion, stack, seed, and nested command status" do
    parent = self()

    error =
      assert_raise ExUnit.AssertionError, fn ->
        Diagnostics.capture(
          diagnostic_context(),
          :test,
          fn ->
            Diagnostics.record_nested_mix(
              "bilimbi.migrate",
              ["--quiet"],
              17,
              @safe_nested_output
            )

            raise_sentinel()
          end,
          snapshot_fun: &safe_snapshot/0,
          write_fun: fn document -> send(parent, {:diagnostic, document}) end
        )
      end

    assert error.message == "SAFE_PLATFORM_BASELINE_SENTINEL"
    assert_receive {:diagnostic, document}
    assert document["format"] == "bilimbi-platform-baseline-failure/v1"
    assert document["source"]["owner"] == "core/compatibility"
    assert document["source"]["phase"] == "test"
    assert document["source"]["test"] == "test safe failure probe"
    assert document["source"]["file"] =~ "platform_baseline_failure_diagnostics_test.exs"
    assert document["run"]["sha"] =~ ~r/^[0-9a-f]{40}$/
    assert document["run"]["seed"] == ExUnit.configuration()[:seed]
    assert document["run"]["order"] == "randomized_by_seed"
    assert document["failure"]["formatted"] =~ "SAFE_PLATFORM_BASELINE_SENTINEL"
    assert Enum.any?(document["failure"]["stack"], &String.contains?(&1, "raise_sentinel"))

    assert [nested] = document["nested_mix"]
    assert nested["task"] == "bilimbi.migrate"
    assert nested["args"] == ["--quiet"]
    assert nested["status"] == 17
    assert nested["output"] == @safe_nested_output
  end

  test "success performs no snapshot, write, directory, or file work" do
    output_dir = temporary_dir("success")
    parent = self()

    assert :ok ==
             Diagnostics.capture(
               diagnostic_context(),
               :test,
               fn -> :ok end,
               output_dir: output_dir,
               snapshot_fun: fn -> send(parent, :snapshot_called) end,
               write_fun: fn _document -> send(parent, :write_called) end
             )

    refute_received :snapshot_called
    refute_received :write_called
    refute File.exists?(output_dir)
  end

  test "redacts credential forms before diagnostic bytes reach disk" do
    output_dir = temporary_dir("redaction")

    failure = """
    password=PASSWORD_CANARY
    token:
    TOKEN_CANARY
    postgres://diagnostic-user:URI_CANARY@localhost/database
    Authorization: Bearer BEARER_CANARY_123456789
    opaque=#{String.duplicate("Ab3", 22)}
    """

    assert_raise ExUnit.AssertionError, fn ->
      Diagnostics.capture(
        diagnostic_context(),
        :test,
        fn ->
          Diagnostics.record_nested_mix(
            "bilimbi.schema.verify",
            [],
            19,
            "cookie=NESTED_COOKIE_CANARY"
          )

          raise ExUnit.AssertionError, message: failure
        end,
        output_dir: output_dir,
        snapshot_fun: &safe_snapshot/0
      )
    end

    assert [path] = diagnostic_files(output_dir)
    bytes = File.read!(path)

    for canary <- [
          "PASSWORD_CANARY",
          "TOKEN_CANARY",
          "URI_CANARY",
          "BEARER_CANARY_123456789",
          "NESTED_COOKIE_CANARY",
          String.duplicate("Ab3", 22)
        ] do
      refute bytes =~ canary
    end

    assert bytes =~ "[REDACTED"
    assert %{"failure" => %{"formatted" => formatted}} = :json.decode(bytes)
    assert formatted =~ "[REDACTED]"

    known_value = "UNLABELED_CONFIGURED_CANARY"

    refute Diagnostics.redact_for_test("value=#{known_value}", [known_value]) =~ known_value
  end

  test "strict validation rejects unknown fields and database result columns" do
    document = captured_document()

    assert_raise ArgumentError, fn ->
      document
      |> Map.put("rogue", "not allowed")
      |> Diagnostics.validate_document!()
    end

    assert_raise ArgumentError, fn ->
      update_in(document, ["failure"], &Map.put(&1, "password", "not allowed"))
      |> Diagnostics.validate_document!()
    end

    settings = safe_settings_result() |> Map.update!(:columns, &(&1 ++ ["query"]))

    assert_raise ArgumentError, fn ->
      Diagnostics.normalize_database_snapshot(
        settings,
        safe_sessions_result(),
        safe_databases_result()
      )
    end

    sessions =
      safe_sessions_result()
      |> Map.put(:rows, [["bilimbi_test_safe", "active", "Client", 1, "SELECT *"]])
      |> Map.update!(:columns, &(&1 ++ ["query"]))

    assert_raise ArgumentError, fn ->
      Diagnostics.normalize_database_snapshot(
        safe_settings_result(),
        sessions,
        safe_databases_result()
      )
    end
  end

  test "normalizes only fixed bounded PostgreSQL aggregate shapes" do
    assert %{
             "status" => "ok",
             "settings" => %{
               "postgresql_version" => "18.1",
               "max_connections" => 100,
               "superuser_reserved_connections" => 3,
               "reserved_connections" => 0
             },
             "sessions" => [
               %{
                 "database" => "bilimbi_test_safe",
                 "state" => "active",
                 "wait_event_type" => "Client",
                 "count" => 2
               }
             ],
             "databases" => [
               %{
                 "database" => "bilimbi_test_bilimbi_e2e_safe",
                 "allows_connections" => true,
                 "count" => 1
               }
             ]
           } =
             Diagnostics.normalize_database_snapshot(
               safe_settings_result(),
               safe_sessions_result(),
               safe_databases_result()
             )
  end

  test "diagnostic snapshot and writer failures preserve the original exception and stack" do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        result =
          try do
            Diagnostics.capture(
              diagnostic_context(),
              :test,
              &raise_sentinel/0,
              snapshot_fun: fn -> raise "snapshot must be generic" end,
              write_fun: fn _document -> raise "writer path must be generic" end
            )
          rescue
            error -> {error, __STACKTRACE__}
          end

        send(parent, {:diagnostic_failure_result, result})
      end)

    assert_receive {:diagnostic_failure_result, {error, stacktrace}}
    assert %ExUnit.AssertionError{message: "SAFE_PLATFORM_BASELINE_SENTINEL"} = error

    assert Enum.any?(stacktrace, fn
             {__MODULE__, :raise_sentinel, 0, _location} -> true
             _entry -> false
           end)

    assert stderr =~ "preserving original failure"
    refute stderr =~ "snapshot must be generic"
    refute stderr =~ "writer path must be generic"
  end

  test "throw and exit reasons are re-raised unchanged" do
    opts = [snapshot_fun: &safe_snapshot/0, write_fun: fn _document -> :ok end]

    assert catch_throw(
             Diagnostics.capture(
               diagnostic_context(),
               :test,
               fn -> throw(:safe_throw) end,
               opts
             )
           ) == :safe_throw

    assert catch_exit(
             Diagnostics.capture(
               diagnostic_context(),
               :test,
               fn -> exit(:safe_exit) end,
               opts
             )
           ) == :safe_exit
  end

  test "failure, stack, and nested command collections remain bounded" do
    parent = self()
    long_output = String.duplicate("safe output line\n", 2_000)
    long_failure = String.duplicate("safe failure line\n", 6_000)

    assert_raise ExUnit.AssertionError, fn ->
      Diagnostics.capture(
        diagnostic_context(),
        :test,
        fn ->
          for status <- 1..6 do
            Diagnostics.record_nested_mix(
              "bilimbi.schema.verify",
              [],
              status,
              long_output
            )
          end

          raise ExUnit.AssertionError, message: long_failure
        end,
        snapshot_fun: &safe_snapshot/0,
        write_fun: fn document -> send(parent, {:bounded, document}) end
      )
    end

    assert_receive {:bounded, document}
    assert byte_size(document["failure"]["formatted"]) <= 64 * 1024
    assert document["failure"]["formatted"] =~ "[TRUNCATED]"
    assert Enum.map(document["nested_mix"], & &1["status"]) == [3, 4, 5, 6]
    assert Enum.all?(document["nested_mix"], & &1["truncated"])
    assert Enum.all?(document["nested_mix"], &(&1["output_bytes"] == byte_size(long_output)))
    assert Enum.all?(document["nested_mix"], &(byte_size(&1["output"]) <= 24 * 1024))
  end

  test "disk capture enforces six files and a 192 KiB per-file ceiling" do
    output_dir = temporary_dir("file-bounds")

    capture_io(:stderr, fn ->
      for _index <- 1..7 do
        assert_raise ExUnit.AssertionError, fn ->
          Diagnostics.capture(
            diagnostic_context(),
            :test,
            &raise_sentinel/0,
            output_dir: output_dir,
            snapshot_fun: &safe_snapshot/0
          )
        end
      end
    end)

    files = diagnostic_files(output_dir)
    assert length(files) == 6
    assert Enum.all?(files, &(File.stat!(&1).size <= 192 * 1024))
  end

  test "unapproved nested commands cannot place dynamic arguments in diagnostics" do
    parent = self()

    assert_raise ExUnit.AssertionError, fn ->
      Diagnostics.capture(
        diagnostic_context(),
        :test,
        fn ->
          Diagnostics.record_nested_mix(
            "run",
            ["-e", "IO.inspect(System.get_env())"],
            29,
            "password=DYNAMIC_ARGUMENT_CANARY"
          )

          raise_sentinel()
        end,
        snapshot_fun: &safe_snapshot/0,
        write_fun: fn document -> send(parent, {:unapproved, document}) end
      )
    end

    assert_receive {:unapproved, document}
    assert [nested] = document["nested_mix"]
    assert nested["task"] == "unapproved"
    assert nested["args"] == []
    refute inspect(document) =~ "System.get_env"
    refute inspect(document) =~ "DYNAMIC_ARGUMENT_CANARY"
  end

  defp captured_document do
    parent = self()

    assert_raise ExUnit.AssertionError, fn ->
      Diagnostics.capture(
        diagnostic_context(),
        :test,
        &raise_sentinel/0,
        snapshot_fun: &safe_snapshot/0,
        write_fun: fn document -> send(parent, {:captured_document, document}) end
      )
    end

    assert_receive {:captured_document, document}
    document
  end

  defp diagnostic_context do
    %{
      module: __MODULE__,
      test: :"test safe failure probe",
      file: __ENV__.file,
      line: __ENV__.line
    }
  end

  defp safe_snapshot do
    Diagnostics.normalize_database_snapshot(
      safe_settings_result(),
      safe_sessions_result(),
      safe_databases_result()
    )
  end

  defp safe_settings_result do
    %{
      columns: [
        "server_version",
        "max_connections",
        "superuser_reserved_connections",
        "reserved_connections"
      ],
      rows: [["18.1", 100, 3, 0]]
    }
  end

  defp safe_sessions_result do
    %{
      columns: ["database", "state", "wait_event_type", "session_count"],
      rows: [["bilimbi_test_safe", "active", "Client", 2]]
    }
  end

  defp safe_databases_result do
    %{
      columns: ["database", "allows_connections", "session_count"],
      rows: [["bilimbi_test_bilimbi_e2e_safe", true, 1]]
    }
  end

  defp temporary_dir(name) do
    Path.join(
      System.tmp_dir!(),
      "bilimbi-platform-baseline-diagnostics-#{name}-#{System.unique_integer([:positive])}"
    )
  end

  defp diagnostic_files(output_dir) do
    output_dir
    |> File.ls!()
    |> Enum.filter(&Regex.match?(~r/\Afailure-[0-9]+\.json\z/, &1))
    |> Enum.sort()
    |> Enum.map(&Path.join(output_dir, &1))
  end

  defp raise_sentinel do
    raise ExUnit.AssertionError, message: "SAFE_PLATFORM_BASELINE_SENTINEL"
  end
end
