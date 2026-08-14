defmodule Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnostics do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Bilimbi.Core.Compatibility.PlatformBaselineTestRepo
  alias Ecto.Adapters.SQL

  @format "bilimbi-platform-baseline-failure/v1"
  @workspace_root Path.expand("../../../../..", __DIR__)
  @default_output_dir Path.join(@workspace_root, "_build/test/e2e-diagnostics")
  @records_key {__MODULE__, :nested_mix}

  @max_files 6
  @max_file_bytes 192 * 1024
  @max_failure_bytes 64 * 1024
  @max_nested_commands 4
  @max_nested_output_bytes 24 * 1024
  @max_stack_frames 40
  @max_text_bytes 4 * 1024

  @allowed_phases [:setup, :test, :cleanup]
  @allowed_parent_commands ["mix precommit", "mix test"]
  @allowed_nested_commands MapSet.new([
                             {"bilimbi.migrate", ["--quiet"]},
                             {"bilimbi.schema.verify", []},
                             {"bilimbi.schema.adopt", []},
                             {"bilimbi.seeds.run", []},
                             {"run",
                              [
                                "-e",
                                "Bilimbi.Core.Compatibility.PlatformBaselineSmoke.run()"
                              ]}
                           ])

  @secret_env_keys ~w(
    BELIMBING_APP_KEY
    DATABASE_URL
    PGPASSWORD
    SECRET_KEY_BASE
  )
  @selector_env_keys ~w(BILIMBI_E2E_DIAGNOSTICS_DIR RUNNER_TEMP)

  @settings_columns [
    "server_version",
    "max_connections",
    "superuser_reserved_connections",
    "reserved_connections"
  ]
  @session_columns ["database", "state", "wait_event_type", "session_count"]
  @database_columns ["database", "allows_connections", "session_count"]

  @session_states [
    nil,
    "active",
    "disabled",
    "fastpath function call",
    "idle",
    "idle in transaction",
    "idle in transaction (aborted)"
  ]
  @wait_event_types [
    nil,
    "Activity",
    "BufferPin",
    "Client",
    "Extension",
    "IO",
    "IPC",
    "InjectionPoint",
    "Lock",
    "LWLock",
    "Timeout"
  ]

  @settings_sql """
  SELECT
    current_setting('server_version') AS server_version,
    current_setting('max_connections')::integer AS max_connections,
    current_setting('superuser_reserved_connections')::integer AS superuser_reserved_connections,
    NULLIF(current_setting('reserved_connections', true), '')::integer AS reserved_connections
  """

  @sessions_sql """
  SELECT
    datname AS database,
    state,
    wait_event_type,
    count(*)::integer AS session_count
  FROM pg_stat_activity
  WHERE datname LIKE $1
  GROUP BY datname, state, wait_event_type
  ORDER BY datname, state NULLS FIRST, wait_event_type NULLS FIRST
  LIMIT $2
  """

  @databases_sql """
  SELECT
    databases.datname AS database,
    databases.datallowconn AS allows_connections,
    count(activity.pid)::integer AS session_count
  FROM pg_database AS databases
  LEFT JOIN pg_stat_activity AS activity ON activity.datid = databases.oid
  WHERE databases.datname LIKE $1
  GROUP BY databases.datname, databases.datallowconn
  ORDER BY databases.datname
  LIMIT $2
  """

  @doc false
  def capture(context, phase, fun, opts \\ [])
      when is_map(context) and phase in @allowed_phases and is_function(fun, 0) do
    opts =
      Keyword.validate!(opts,
        output_dir: nil,
        snapshot_fun: &database_snapshot/0,
        write_fun: nil
      )

    Process.put(@records_key, [])

    try do
      fun.()
    catch
      kind, reason when kind in [:error, :exit, :throw] ->
        stacktrace = __STACKTRACE__
        safely_write_diagnostic(context, phase, kind, reason, stacktrace, opts)
        :erlang.raise(kind, reason, stacktrace)
    after
      Process.delete(@records_key)
    end
  end

  @doc false
  def record_nested_mix(task, args, status, output) do
    entry = normalize_nested_command(task, args, status, output)
    entries = Process.get(@records_key, [])
    Process.put(@records_key, Enum.take(entries ++ [entry], -@max_nested_commands))
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  @doc false
  def normalize_database_snapshot(settings_result, sessions_result, databases_result) do
    settings = normalize_settings_result!(settings_result)
    sessions = normalize_sessions_result!(sessions_result)
    databases = normalize_databases_result!(databases_result)

    %{
      "status" => "ok",
      "settings" => settings,
      "sessions" => sessions,
      "databases" => databases
    }
  end

  @doc false
  def validate_document!(document) when is_map(document) do
    exact_keys!(document, ~w(format captured_at source run runtime failure nested_mix database))
    exact_value!(document["format"], @format)
    bounded_binary!(document["captured_at"], 64)
    validate_source!(document["source"])
    validate_run!(document["run"])
    validate_runtime!(document["runtime"])
    validate_failure!(document["failure"])
    validate_nested_mix!(document["nested_mix"])
    validate_database!(document["database"])
    document
  end

  def validate_document!(_document), do: raise(ArgumentError, "diagnostic must be a map")

  @doc false
  def redact_for_test(value, forbidden_values)
      when is_binary(value) and is_list(forbidden_values) do
    redact(value, forbidden_values)
  end

  defp safely_write_diagnostic(context, phase, kind, reason, stacktrace, opts) do
    snapshot = safely_snapshot(opts[:snapshot_fun])
    document = build_document(context, phase, kind, reason, stacktrace, snapshot)

    case opts[:write_fun] do
      fun when is_function(fun, 1) ->
        fun.(document)

      nil ->
        output_dir = opts[:output_dir] || diagnostics_dir()
        write_document(document, output_dir)
    end
  rescue
    _error -> warn_diagnostic_failure()
  catch
    _kind, _reason -> warn_diagnostic_failure()
  end

  defp safely_snapshot(snapshot_fun) do
    snapshot_fun.()
  rescue
    _error -> unavailable_database("query_failed")
  catch
    :exit, _reason -> unavailable_database("connection_unavailable")
    _kind, _reason -> unavailable_database("query_failed")
  end

  defp build_document(context, phase, kind, reason, stacktrace, snapshot) do
    forbidden_values = forbidden_values()
    formatted_failure = Exception.format(kind, reason, stacktrace)

    %{
      "format" => @format,
      "captured_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "source" => source(context, phase, forbidden_values),
      "run" => run_identity(forbidden_values),
      "runtime" => runtime(),
      "failure" => %{
        "kind" => Atom.to_string(kind),
        "exception" => exception_module(reason),
        "formatted" =>
          formatted_failure
          |> redact(forbidden_values)
          |> truncate_text(@max_failure_bytes, 48 * 1024)
          |> elem(0),
        "stack" => normalize_stacktrace(stacktrace, forbidden_values)
      },
      "nested_mix" => nested_mix(forbidden_values),
      "database" => snapshot
    }
    |> validate_document!()
  end

  defp source(context, phase, forbidden_values) do
    %{
      "owner" => "core/compatibility",
      "phase" => Atom.to_string(phase),
      "module" => context |> Map.get(:module) |> module_name() |> redact(forbidden_values),
      "test" => context |> Map.get(:test) |> test_name() |> redact(forbidden_values),
      "file" => context |> Map.get(:file) |> workspace_relative_path(),
      "line" => normalize_line(Map.get(context, :line))
    }
  end

  defp run_identity(forbidden_values) do
    github_sha = validated_sha(System.get_env("GITHUB_SHA"))
    github_ref = bounded_optional_env("GITHUB_REF_NAME", forbidden_values)
    github_run_id = numeric_optional_env("GITHUB_RUN_ID")
    github_run_attempt = numeric_optional_env("GITHUB_RUN_ATTEMPT")
    github_job = bounded_optional_env("GITHUB_JOB", forbidden_values)

    %{
      "sha" => github_sha || safe_git(["rev-parse", "HEAD"], &validated_sha/1),
      "ref" => github_ref || safe_git(["branch", "--show-current"], &bounded_ref/1),
      "run_id" => github_run_id,
      "run_attempt" => github_run_attempt,
      "job" => github_job,
      "origin" => if(github_run_id, do: "github_actions", else: "local"),
      "parent_command" => parent_command(),
      "seed" => ExUnit.configuration()[:seed],
      "order" => "randomized_by_seed"
    }
  end

  defp runtime do
    %{
      "elixir" => System.version(),
      "otp" => :erlang.system_info(:otp_release) |> List.to_string(),
      "pool_sizes" => %{
        "repo" => repo_pool_size(Repo),
        "migration_test_repo" => repo_pool_size(MigrationTestRepo),
        "platform_baseline_test_repo" => repo_pool_size(PlatformBaselineTestRepo)
      }
    }
  end

  defp nested_mix(forbidden_values) do
    @records_key
    |> Process.get([])
    |> Enum.map(fn entry ->
      %{
        "task" => entry.task,
        "args" => entry.args,
        "status" => entry.status,
        "output_bytes" => entry.output_bytes,
        "truncated" => entry.truncated,
        "output" => redact(entry.output, forbidden_values)
      }
    end)
  end

  defp normalize_nested_command(task, args, status, output)
       when is_binary(task) and is_list(args) and is_integer(status) and is_binary(output) do
    {safe_task, safe_args} =
      if MapSet.member?(@allowed_nested_commands, {task, args}) do
        {task, args}
      else
        {"unapproved", []}
      end

    output = String.replace_invalid(output)
    output_bytes = byte_size(output)
    {output, truncated} = truncate_text(output, @max_nested_output_bytes, 16 * 1024)

    %{
      task: safe_task,
      args: safe_args,
      status: status,
      output_bytes: output_bytes,
      truncated: truncated,
      output: output
    }
  end

  defp normalize_nested_command(_task, _args, _status, _output) do
    %{
      task: "unapproved",
      args: [],
      status: -1,
      output_bytes: 0,
      truncated: false,
      output: ""
    }
  end

  defp database_snapshot do
    if Process.whereis(MigrationTestRepo) do
      with {:ok, settings} <- SQL.query(MigrationTestRepo, @settings_sql, [], timeout: 2_000),
           {:ok, sessions} <-
             SQL.query(MigrationTestRepo, @sessions_sql, ["bilimbi_test%", 50], timeout: 2_000),
           {:ok, databases} <-
             SQL.query(
               MigrationTestRepo,
               @databases_sql,
               ["bilimbi_test_bilimbi_e2e_%", 25],
               timeout: 2_000
             ) do
        normalize_database_snapshot(settings, sessions, databases)
      else
        {:error, _error} -> unavailable_database("query_failed")
      end
    else
      unavailable_database("connection_unavailable")
    end
  rescue
    _error -> unavailable_database("query_failed")
  catch
    :exit, _reason -> unavailable_database("connection_unavailable")
    _kind, _reason -> unavailable_database("query_failed")
  end

  defp unavailable_database(status) do
    %{"status" => status, "settings" => nil, "sessions" => [], "databases" => []}
  end

  defp normalize_settings_result!(%{
         columns: @settings_columns,
         rows: [[version, max_connections, superuser_reserved, reserved]]
       }) do
    %{
      "postgresql_version" => bounded_binary!(version, 128),
      "max_connections" => validated_positive_integer!(max_connections),
      "superuser_reserved_connections" => validated_non_negative_integer!(superuser_reserved),
      "reserved_connections" => validated_optional_non_negative_integer!(reserved)
    }
  end

  defp normalize_settings_result!(_result) do
    raise ArgumentError, "unexpected PostgreSQL settings diagnostic columns"
  end

  defp validated_positive_integer!(value) when is_integer(value) and value > 0, do: value

  defp validated_positive_integer!(_value) do
    raise ArgumentError, "unexpected PostgreSQL settings diagnostic shape"
  end

  defp validated_non_negative_integer!(value) when is_integer(value) and value >= 0, do: value

  defp validated_non_negative_integer!(_value) do
    raise ArgumentError, "unexpected PostgreSQL settings diagnostic shape"
  end

  defp validated_optional_non_negative_integer!(nil), do: nil

  defp validated_optional_non_negative_integer!(value),
    do: validated_non_negative_integer!(value)

  defp normalize_sessions_result!(%{columns: @session_columns, rows: rows})
       when is_list(rows) and length(rows) <= 50 do
    Enum.map(rows, fn
      [database, state, wait_event_type, count]
      when is_binary(database) and state in @session_states and
             wait_event_type in @wait_event_types and is_integer(count) and count >= 0 ->
        unless String.starts_with?(database, "bilimbi_test") and byte_size(database) <= 63 do
          raise ArgumentError, "unexpected PostgreSQL session database"
        end

        %{
          "database" => database,
          "state" => state,
          "wait_event_type" => wait_event_type,
          "count" => count
        }

      _row ->
        raise ArgumentError, "unexpected PostgreSQL session diagnostic row"
    end)
  end

  defp normalize_sessions_result!(_result) do
    raise ArgumentError, "unexpected PostgreSQL session diagnostic columns"
  end

  defp normalize_databases_result!(%{columns: @database_columns, rows: rows})
       when is_list(rows) and length(rows) <= 25 do
    Enum.map(rows, fn
      [database, allows_connections, count]
      when is_binary(database) and is_boolean(allows_connections) and is_integer(count) and
             count >= 0 ->
        unless String.starts_with?(database, "bilimbi_test_bilimbi_e2e_") and
                 byte_size(database) <= 63 do
          raise ArgumentError, "unexpected PostgreSQL E2E database"
        end

        %{
          "database" => database,
          "allows_connections" => allows_connections,
          "count" => count
        }

      _row ->
        raise ArgumentError, "unexpected PostgreSQL database diagnostic row"
    end)
  end

  defp normalize_databases_result!(_result) do
    raise ArgumentError, "unexpected PostgreSQL database diagnostic columns"
  end

  defp write_document(document, output_dir) when is_binary(output_dir) do
    document = validate_document!(document)
    encoded = document |> json_term() |> :json.encode() |> IO.iodata_to_binary()

    if byte_size(encoded) > @max_file_bytes do
      raise ArgumentError, "diagnostic exceeds file size budget"
    end

    File.mkdir_p!(output_dir)

    diagnostic_file_count =
      output_dir
      |> File.ls!()
      |> Enum.count(&Regex.match?(~r/\Afailure-[0-9]+\.json\z/, &1))

    if diagnostic_file_count >= @max_files do
      raise ArgumentError, "diagnostic file count budget exhausted"
    end

    basename = "failure-#{System.unique_integer([:positive, :monotonic])}"
    temporary = Path.join(output_dir, ".#{basename}.tmp")
    destination = Path.join(output_dir, "#{basename}.json")

    File.write!(temporary, encoded, [:binary, :exclusive])
    File.rename!(temporary, destination)
    :ok
  end

  defp json_term(nil), do: :null

  defp json_term(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, json_term(nested)} end)
  end

  defp json_term(value) when is_list(value), do: Enum.map(value, &json_term/1)
  defp json_term(value), do: value

  defp diagnostics_dir do
    override = nonempty_env("BILIMBI_E2E_DIAGNOSTICS_DIR")

    if System.get_env("GITHUB_ACTIONS") == "true" do
      runner_temp = required_absolute_env!("RUNNER_TEMP")
      contained_output_dir!(override || runner_temp, runner_temp)
    else
      contained_output_dir!(override || @default_output_dir, @default_output_dir)
    end
  end

  defp forbidden_values do
    env_values = Enum.map(@secret_env_keys, &System.get_env/1)
    selector_values = Enum.map(@selector_env_keys, &System.get_env/1)
    configured_values = [Application.get_env(:bilimbi_base_settings, :belimbing_app_key)]
    repo_values = repo_secret_values()

    [System.user_home() | env_values ++ selector_values ++ configured_values ++ repo_values]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.sort_by(&byte_size/1, :desc)
  end

  defp nonempty_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp required_absolute_env!(name) do
    case nonempty_env(name) do
      nil ->
        raise ArgumentError, "diagnostic Actions output root is unavailable"

      value ->
        if Path.type(value) == :absolute do
          Path.expand(value)
        else
          raise ArgumentError, "diagnostic Actions output root is unavailable"
        end
    end
  end

  defp contained_output_dir!(path, root) when is_binary(path) and is_binary(root) do
    root = Path.expand(root)

    candidate =
      case Path.type(path) do
        :absolute -> Path.expand(path)
        :relative -> Path.expand(path, root)
        _other -> raise ArgumentError, "diagnostic output path is invalid"
      end

    relative = Path.relative_to(candidate, root)

    unless relative == "." or contained_relative_path?(relative) do
      raise ArgumentError, "diagnostic output path escapes its allowed root"
    end

    reject_existing_symlink_descendants!(root, relative)
    candidate
  end

  defp contained_relative_path?(relative) do
    Path.type(relative) == :relative and
      case Path.split(relative) do
        [".." | _rest] -> false
        parts -> Enum.all?(parts, &(&1 not in [".", ".."]))
      end
  end

  defp reject_existing_symlink_descendants!(_root, "."), do: :ok

  defp reject_existing_symlink_descendants!(root, relative) do
    _last_checked =
      relative
      |> Path.split()
      |> Enum.reduce_while(root, fn part, parent ->
        current = Path.join(parent, part)

        case File.lstat(current) do
          {:ok, %File.Stat{type: :symlink}} ->
            raise ArgumentError, "diagnostic output path crosses a symbolic link"

          {:ok, _stat} ->
            {:cont, current}

          {:error, :enoent} ->
            {:halt, current}

          {:error, _reason} ->
            raise ArgumentError, "diagnostic output path cannot be inspected"
        end
      end)

    :ok
  end

  defp repo_secret_values do
    Repo.config()
    |> Keyword.take([:password, :url])
    |> Keyword.values()
  rescue
    _error -> []
  end

  defp redact(value, forbidden_values) when is_binary(value) do
    value
    |> String.replace_invalid()
    |> String.replace(@workspace_root, ".")
    |> replace_forbidden_values(forbidden_values)
    |> replace_regex(
      ~r/(?:[a-z][a-z0-9+.-]*:\/\/)[^\s\/:@]+:[^\s\/@]+@/iu,
      fn match -> Regex.replace(~r/[^\/:@]+:[^\/@]+@$/u, match, "[REDACTED]@") end
    )
    |> replace_regex(
      ~r/(?i)(Authorization\s*[:=]\s*)(?:(?:Bearer|Basic)\s+)?[^\s,;}\]]+/u,
      "\\1[REDACTED]"
    )
    |> replace_regex(
      ~r/(?i)(["']?(?:password|passwd|secret|token|api[-_]?key|cookie|session|payload|hash)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;}\]]+)/u,
      "\\1[REDACTED]"
    )
    |> replace_regex(~r/(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+\/=:-]+/u, "\\1 [REDACTED]")
    |> replace_regex(
      ~r/\b(?=[A-Za-z0-9+_=.-]{48,}\b)(?=[A-Za-z0-9+_=.-]*[A-Z])(?=[A-Za-z0-9+_=.-]*[a-z])(?=[A-Za-z0-9+_=.-]*[0-9])[A-Za-z0-9+_=.-]+\b/u,
      "[REDACTED_OPAQUE]"
    )
  end

  defp replace_regex(value, regex, replacement), do: Regex.replace(regex, value, replacement)

  defp replace_forbidden_values(value, forbidden_values) do
    Enum.reduce(forbidden_values, value, fn forbidden, output ->
      String.replace(output, forbidden, "[REDACTED]")
    end)
  end

  defp normalize_stacktrace(stacktrace, forbidden_values) do
    stacktrace
    |> Enum.take(@max_stack_frames)
    |> Enum.map(fn entry ->
      entry
      |> Exception.format_stacktrace_entry()
      |> redact(forbidden_values)
      |> truncate_text(@max_text_bytes, 3 * 1024)
      |> elem(0)
    end)
  end

  defp exception_module(%{__struct__: module}) when is_atom(module), do: inspect(module)
  defp exception_module(_reason), do: nil

  defp module_name(module) when is_atom(module), do: inspect(module)
  defp module_name(_module), do: "unknown"

  defp test_name(test) when is_atom(test), do: Atom.to_string(test)
  defp test_name(_test), do: "unknown"

  defp normalize_line(line) when is_integer(line) and line > 0, do: line
  defp normalize_line(_line), do: nil

  defp workspace_relative_path(nil), do: "unknown"

  defp workspace_relative_path(path) do
    expanded = Path.expand(to_string(path), @workspace_root)
    relative = Path.relative_to(expanded, @workspace_root)

    if relative == ".." or String.starts_with?(relative, "../") or
         String.starts_with?(relative, "..\\") or Path.type(relative) == :absolute do
      "outside-workspace-redacted"
    else
      String.replace(relative, "\\", "/")
    end
  end

  defp validated_sha(value) when is_binary(value) do
    value = String.trim(value)
    if Regex.match?(~r/\A[0-9a-f]{40}\z/, value), do: value
  end

  defp validated_sha(_value), do: nil

  defp bounded_ref(value) when is_binary(value) do
    value = String.trim(value)

    if value != "" and byte_size(value) <= 255 and String.printable?(value) do
      value
    end
  end

  defp bounded_ref(_value), do: nil

  defp bounded_optional_env(name, forbidden_values) do
    case System.get_env(name) do
      value when is_binary(value) -> value |> redact(forbidden_values) |> bounded_ref()
      _other -> nil
    end
  end

  defp numeric_optional_env(name) do
    case System.get_env(name) do
      value when is_binary(value) ->
        value = String.trim(value)
        if Regex.match?(~r/\A[0-9]{1,20}\z/, value), do: value

      _other ->
        nil
    end
  end

  defp safe_git(args, normalizer) do
    case System.cmd("git", args,
           cd: @workspace_root,
           stderr_to_stdout: true,
           env: [{"GIT_CONFIG_NOSYSTEM", "1"}]
         ) do
      {output, 0} -> normalizer.(output)
      {_output, _status} -> nil
    end
  rescue
    _error -> nil
  end

  defp parent_command do
    case System.get_env("BILIMBI_E2E_PARENT_COMMAND") do
      value when value in @allowed_parent_commands -> value
      _other -> "unknown"
    end
  end

  defp repo_pool_size(repo) do
    case repo.config()[:pool_size] do
      value when is_integer(value) and value > 0 -> value
      _other -> nil
    end
  rescue
    _error -> nil
  end

  defp truncate_text(value, limit, _head_bytes)
       when is_binary(value) and byte_size(value) <= limit do
    {value, false}
  end

  defp truncate_text(value, limit, head_bytes) when is_binary(value) do
    marker = "\n...[TRUNCATED]...\n"
    tail_bytes = limit - head_bytes - byte_size(marker)
    tail_start = byte_size(value) - tail_bytes

    truncated =
      binary_part(value, 0, head_bytes) <>
        marker <> binary_part(value, tail_start, tail_bytes)

    {String.replace_invalid(truncated), true}
  end

  defp validate_source!(source) do
    exact_keys!(source, ~w(owner phase module test file line))
    exact_value!(source["owner"], "core/compatibility")
    member!(source["phase"], ~w(setup test cleanup))
    bounded_binary!(source["module"], @max_text_bytes)
    bounded_binary!(source["test"], @max_text_bytes)
    bounded_binary!(source["file"], 1_024)
    optional_positive_integer!(source["line"])
  end

  defp validate_run!(run) do
    exact_keys!(
      run,
      ~w(sha ref run_id run_attempt job origin parent_command seed order)
    )

    optional_sha!(run["sha"])
    optional_bounded_binary!(run["ref"], 255)
    optional_numeric_string!(run["run_id"])
    optional_numeric_string!(run["run_attempt"])
    optional_bounded_binary!(run["job"], 255)
    member!(run["origin"], ~w(github_actions local))
    member!(run["parent_command"], ["mix precommit", "mix test", "unknown"])
    non_negative_integer!(run["seed"])
    exact_value!(run["order"], "randomized_by_seed")
  end

  defp validate_runtime!(runtime) do
    exact_keys!(runtime, ~w(elixir otp pool_sizes))
    bounded_binary!(runtime["elixir"], 64)
    bounded_binary!(runtime["otp"], 64)

    pool_sizes = runtime["pool_sizes"]
    exact_keys!(pool_sizes, ~w(repo migration_test_repo platform_baseline_test_repo))
    Enum.each(Map.values(pool_sizes), &optional_positive_integer!/1)
  end

  defp validate_failure!(failure) do
    exact_keys!(failure, ~w(kind exception formatted stack))
    member!(failure["kind"], ~w(error exit throw))
    optional_bounded_binary!(failure["exception"], 255)
    bounded_binary!(failure["formatted"], @max_failure_bytes)

    stack = failure["stack"]

    unless is_list(stack) and length(stack) <= @max_stack_frames do
      raise ArgumentError, "diagnostic stack exceeds frame budget"
    end

    Enum.each(stack, &bounded_binary!(&1, @max_text_bytes))
  end

  defp validate_nested_mix!(entries)
       when is_list(entries) and length(entries) <= @max_nested_commands do
    Enum.each(entries, fn entry ->
      exact_keys!(entry, ~w(task args status output_bytes truncated output))
      member!(entry["task"], ["unapproved" | Enum.map(@allowed_nested_commands, &elem(&1, 0))])

      unless is_list(entry["args"]) and length(entry["args"]) <= 3 do
        raise ArgumentError, "diagnostic nested command arguments are invalid"
      end

      Enum.each(entry["args"], &bounded_binary!(&1, @max_text_bytes))
      integer!(entry["status"])
      non_negative_integer!(entry["output_bytes"])
      boolean!(entry["truncated"])
      bounded_binary!(entry["output"], @max_nested_output_bytes)
    end)
  end

  defp validate_nested_mix!(_entries) do
    raise ArgumentError, "diagnostic nested commands exceed budget"
  end

  defp validate_database!(database) do
    exact_keys!(database, ~w(status settings sessions databases))
    member!(database["status"], ~w(ok query_failed connection_unavailable timeout))

    if database["status"] == "ok" do
      settings = database["settings"]

      exact_keys!(
        settings,
        ~w(postgresql_version max_connections superuser_reserved_connections reserved_connections)
      )

      bounded_binary!(settings["postgresql_version"], 128)
      positive_integer!(settings["max_connections"])
      non_negative_integer!(settings["superuser_reserved_connections"])
      optional_non_negative_integer!(settings["reserved_connections"])
      validate_session_rows!(database["sessions"])
      validate_database_rows!(database["databases"])
    else
      exact_value!(database["settings"], nil)
      exact_value!(database["sessions"], [])
      exact_value!(database["databases"], [])
    end
  end

  defp validate_session_rows!(rows) when is_list(rows) and length(rows) <= 50 do
    Enum.each(rows, fn row ->
      exact_keys!(row, ~w(database state wait_event_type count))
      bounded_binary!(row["database"], 63)
      member!(row["state"], @session_states)
      member!(row["wait_event_type"], @wait_event_types)
      non_negative_integer!(row["count"])
    end)
  end

  defp validate_session_rows!(_rows), do: raise(ArgumentError, "invalid session rows")

  defp validate_database_rows!(rows) when is_list(rows) and length(rows) <= 25 do
    Enum.each(rows, fn row ->
      exact_keys!(row, ~w(database allows_connections count))
      bounded_binary!(row["database"], 63)
      boolean!(row["allows_connections"])
      non_negative_integer!(row["count"])
    end)
  end

  defp validate_database_rows!(_rows), do: raise(ArgumentError, "invalid database rows")

  defp exact_keys!(map, keys) when is_map(map) do
    unless Enum.sort(Map.keys(map)) == Enum.sort(keys) do
      raise ArgumentError, "diagnostic contains unknown or missing fields"
    end
  end

  defp exact_keys!(_map, _keys), do: raise(ArgumentError, "diagnostic field must be a map")

  defp exact_value!(value, value), do: :ok
  defp exact_value!(_value, _expected), do: raise(ArgumentError, "unexpected diagnostic value")

  defp member!(value, allowed) do
    unless value in allowed, do: raise(ArgumentError, "unexpected diagnostic enum")
  end

  defp bounded_binary!(value, limit) when is_binary(value) and byte_size(value) <= limit,
    do: value

  defp bounded_binary!(_value, _limit),
    do: raise(ArgumentError, "diagnostic string exceeds budget")

  defp optional_bounded_binary!(nil, _limit), do: :ok
  defp optional_bounded_binary!(value, limit), do: bounded_binary!(value, limit)

  defp optional_sha!(nil), do: :ok

  defp optional_sha!(value) do
    unless validated_sha(value) == value, do: raise(ArgumentError, "invalid diagnostic SHA")
  end

  defp optional_numeric_string!(nil), do: :ok

  defp optional_numeric_string!(value) when is_binary(value) do
    unless Regex.match?(~r/\A[0-9]{1,20}\z/, value) do
      raise ArgumentError, "invalid diagnostic numeric identity"
    end
  end

  defp optional_numeric_string!(_value) do
    raise ArgumentError, "invalid diagnostic numeric identity"
  end

  defp integer!(value) when is_integer(value), do: :ok
  defp integer!(_value), do: raise(ArgumentError, "diagnostic integer is invalid")

  defp positive_integer!(value) when is_integer(value) and value > 0, do: :ok
  defp positive_integer!(_value), do: raise(ArgumentError, "diagnostic integer is invalid")

  defp non_negative_integer!(value) when is_integer(value) and value >= 0, do: :ok
  defp non_negative_integer!(_value), do: raise(ArgumentError, "diagnostic integer is invalid")

  defp optional_positive_integer!(nil), do: :ok
  defp optional_positive_integer!(value), do: positive_integer!(value)

  defp optional_non_negative_integer!(nil), do: :ok
  defp optional_non_negative_integer!(value), do: non_negative_integer!(value)

  defp boolean!(value) when is_boolean(value), do: :ok
  defp boolean!(_value), do: raise(ArgumentError, "diagnostic boolean is invalid")

  defp warn_diagnostic_failure do
    IO.warn(
      "PlatformBaseline failure diagnostics could not be written; preserving original failure"
    )

    :ok
  end
end
