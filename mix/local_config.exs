defmodule Bilimbi.LocalConfig do
  @moduledoc """
  Source-loaded development bootstrap configuration, shared by Mix and the
  local HTTPS shell entry point. This is not application/operator settings.
  Shell overrides are applied after validating the entire checkout-local file.
  HTTPS allocation updates only its section, preserving database credentials.
  """

  def load(root) do
    root = Path.expand(root)
    path = Path.join(root, ".local/config.json")
    config = read(path)
    validate!(config, root, path)
    legacy = Path.join(root, ".local/https/instance.json")

    config =
      if File.exists?(legacy) do
        https = read(legacy)
        validate_https!(https, root, legacy)
        merged = Map.merge(https, Map.get(config, "https", %{}))
        config = Map.put(config, "https", merged)
        write!(root, config)
        File.rm!(legacy)
        config
      else
        config
      end

    config
  end

  def database_options(config) do
    case System.get_env("DATABASE_URL") do
      nil ->
        database = Map.get(config, "database", %{})

        [
          username:
            string!(
              System.get_env("PGUSER") || database["username"] || "bilimbi",
              "PGUSER/database.username"
            ),
          password:
            string!(
              System.get_env("PGPASSWORD") || database["password"] || "bilimbi_dev_ca658ad7d8b5",
              "PGPASSWORD/database.password",
              true
            ),
          hostname:
            string!(
              System.get_env("PGHOST") || database["host"] || "localhost",
              "PGHOST/database.host"
            ),
          port: env_port!("PGPORT", database["port"] || 5433, 1),
          database:
            string!(
              System.get_env("PGDATABASE") || database["name"] || "bilimbi_dev",
              "PGDATABASE/database.name"
            )
        ]

      url ->
        if String.trim(url) == "", do: raise(ArgumentError, "DATABASE_URL must not be empty")
        [url: url]
    end
  end

  def https_options(config) do
    https = Map.get(config, "https", %{})
    host = System.get_env("BILIMBI_DEV_HOST") || https["host"] || "bilimbi.localhost"
    validate_host!(host, "BILIMBI_DEV_HOST/https.host")
    %{host: host, port: env_port!("PORT", https["port"] || 4000, 1024)}
  end

  def save_https!(root, host, port) do
    root = Path.expand(root)
    config = load(root)
    https = %{"root" => root, "host" => host, "port" => port}
    config = Map.put(config, "https", https)
    write!(root, config)
  end

  defp read(path) do
    case File.read(path) do
      {:ok, json} ->
        try do
          :json.decode(json)
        rescue
          _ -> raise ArgumentError, "#{path}: malformed JSON"
        end

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read local config", path: path
    end
  end

  defp validate!(config, root, path) do
    object!(config, ["database", "https"], path)

    if Map.has_key?(config, "database") do
      database = config["database"]
      object!(database, ["name", "host", "port", "username", "password"], "#{path}: database")

      for key <- ["name", "host", "username", "password"], Map.has_key?(database, key) do
        string!(database[key], "#{path}: database.#{key}", key == "password")
      end

      if Map.has_key?(database, "port"), do: port!(database["port"], "#{path}: database.port", 1)
    end

    if Map.has_key?(config, "https"), do: validate_https!(config["https"], root, path)
  end

  defp validate_https!(https, root, path) do
    object!(https, ["root", "host", "port"], "#{path}: https")

    if Map.has_key?(https, "root"), do: string!(https["root"], "#{path}: https.root")

    if Map.has_key?(https, "root") and https["root"] != root do
      raise ArgumentError,
            "#{path}: https.root belongs to another checkout; remove the https section to allocate this checkout's address"
    end

    if Map.has_key?(https, "host"), do: validate_host!(https["host"], "#{path}: https.host")
    if Map.has_key?(https, "port"), do: port!(https["port"], "#{path}: https.port", 1024)
  end

  defp object!(value, keys, path) do
    unless is_map(value), do: raise(ArgumentError, "#{path} must be a JSON object")

    if Enum.any?(Map.keys(value), &(&1 not in keys)) do
      raise ArgumentError,
            "#{path} contains an unknown field; allowed fields: #{Enum.join(keys, ", ")}"
    end
  end

  defp validate_host!(host, path) do
    unless is_binary(host) and byte_size(host) <= 253 and
             Regex.match?(~r/\A([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+localhost\z/, host) and
             Enum.all?(String.split(host, "."), &(byte_size(&1) <= 63)) do
      raise ArgumentError, "#{path} must be a lowercase hostname under .localhost"
    end
  end

  defp string!(value, path, allow_empty \\ false) do
    unless is_binary(value) and not String.contains?(value, <<0>>) and
             (allow_empty or String.trim(value) != "") do
      raise ArgumentError,
            "#{path} must be a valid string#{if allow_empty, do: "", else: " that is not empty"}"
    end

    value
  end

  defp env_port!(name, default, minimum) do
    case System.get_env(name) do
      nil ->
        port!(default, name, minimum)

      value ->
        case Integer.parse(value) do
          {port, ""} -> port!(port, name, minimum)
          _ -> raise ArgumentError, "#{name} must be an integer between #{minimum} and 65535"
        end
    end
  end

  defp port!(port, path, minimum) do
    unless is_integer(port) and port >= minimum and port <= 65535 do
      raise ArgumentError, "#{path} must be an integer between #{minimum} and 65535"
    end

    port
  end

  defp write!(root, config) do
    path = Path.join(root, ".local/config.json")
    validate!(config, root, path)
    File.mkdir_p!(Path.dirname(path))
    temporary = "#{path}.#{System.pid()}.#{System.unique_integer([:positive])}"

    try do
      File.open!(temporary, [:write, :exclusive], fn file ->
        File.chmod!(temporary, 0o600)

        IO.binwrite(
          file,
          :json.format(config, &format_json/3)
        )
      end)

      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end

  # OTP's default formatter puts single-field objects on one line. Keep every
  # setting on its own line so operators can edit and compare this file easily.
  defp format_json(value, encode, state) when is_map(value) and map_size(value) > 0 do
    next_state = %{state | level: state.level + 1}
    indent = String.duplicate(" ", next_state.level * state.indent)

    entries =
      value
      |> Enum.sort()
      |> Enum.map(fn {key, value} ->
        [indent, :json.encode(key), ": ", encode.(value, encode, next_state)]
      end)

    [
      "{\n",
      Enum.intersperse(entries, ",\n"),
      "\n",
      String.duplicate(" ", state.level * state.indent),
      "}"
    ]
  end

  defp format_json(value, encode, state), do: :json.format_value(value, encode, state)
end
