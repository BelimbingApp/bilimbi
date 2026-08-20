defmodule Bilimbi.Base.System do
  @moduledoc """
  Read-only facts about the running instance, for the System Info screen.

  Ports Belimbing's `app/Base/System/Livewire/Info/Index.php`. That component
  answers six questions -- what is the application, what is the runtime, what
  is the database, what is the host, what is loaded, and is anything unhealthy
  -- and half its rows are facts about PHP. This module ports the *questions*,
  not the strings: `Memory Limit` becomes memory **in use**, because the BEAM
  has no configured ceiling and reporting a limit that does not exist would be
  a lie; `PHP Extensions` becomes loaded OTP applications with their versions.

  Belimbing's `Filesystem` card is deliberately absent. Its writable paths are
  Laravel's own `storage/framework/*` and `bootstrap/cache`, which Phoenix has
  no counterpart for; checking invented paths would report health we never
  actually depend on.

  Every probe here is expected to fail on some host somewhere, so each returns
  `:unavailable` rather than raising. A System Info screen that crashes because
  it could not read a disk is worse than one that says it could not read a disk.
  """

  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Repo

  @typedoc "A single labelled fact. `value` is `:unavailable` when it could not be read."
  @type fact :: %{label: String.t(), value: String.t() | :unavailable}

  @doc "Application identity and configuration."
  @spec application() :: [fact()]
  def application do
    [
      fact("Version", Application.get_env(:bilimbi_base_ui, :app_version, "0.1.0")),
      fact("Environment", to_string(environment())),
      fact("Debug Mode", if(debug?(), do: "Enabled", else: "Disabled")),
      fact("URL", endpoint_url()),
      fact("Timezone", Application.get_env(:bilimbi_base_ui, :timezone, "Etc/UTC")),
      fact("Locale", Application.get_env(:bilimbi_base_ui, :locale, "en"))
    ]
  end

  @doc """
  Runtime facts, in place of Belimbing's PHP card.

  `Memory In Use` replaces `Memory Limit`: the BEAM allocates on demand and has
  no `memory_limit` equivalent, so the honest answer is what is currently held.
  """
  @spec runtime() :: [fact()]
  def runtime do
    [
      fact("Elixir", System.version()),
      fact("OTP Release", System.otp_release()),
      fact("ERTS", to_string(:erlang.system_info(:version))),
      fact("Schedulers Online", to_string(:erlang.system_info(:schedulers_online))),
      fact("Memory In Use", format_bytes(:erlang.memory(:total))),
      fact(
        "Processes",
        "#{:erlang.system_info(:process_count)} of #{:erlang.system_info(:process_limit)}"
      )
    ]
  end

  @doc """
  Database configuration plus a live connection check.

  Belimbing's card reports configuration only; #319 asks for status, so the
  connection is actually exercised rather than assumed from config being present.
  """
  @spec database() :: [fact()]
  def database do
    config = Repo.config()

    [
      fact("Adapter", inspect(Repo.__adapter__())),
      fact("Database", config[:database]),
      fact("Host", config[:hostname]),
      fact("Pool Size", config[:pool_size]),
      fact("Connection", connection_status())
    ]
  end

  @doc "Host facts. Disk figures come from `:disksup`, which is not started everywhere."
  @spec server() :: [fact()]
  def server do
    {family, name} = :os.type()

    [
      fact("OS", "#{family} #{name} #{:erlang.system_info(:system_architecture)}"),
      fact("Hostname", hostname()),
      fact("Disk Free", disk(:free)),
      fact("Disk Total", disk(:total))
    ]
  end

  @doc """
  Subsystems whose health the screen reports.

  Queue health comes from Base Queue's redacted diagnostic boundary. It never
  includes job arguments, failure text, stack traces, or transport schemas.
  """
  @spec health() :: [fact()]
  def health do
    [
      fact("Database", connection_status()),
      fact("Cache", "In-memory (ETS)"),
      fact("Queue", Queue.health_status())
    ]
  end

  @doc "Loaded OTP applications with versions, in place of Belimbing's PHP extension list."
  @spec applications() :: [%{name: String.t(), version: String.t()}]
  def applications do
    Application.loaded_applications()
    |> Enum.map(fn {name, _description, version} ->
      %{name: to_string(name), version: to_string(version)}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp fact(label, nil), do: %{label: label, value: :unavailable}
  defp fact(label, :unavailable), do: %{label: label, value: :unavailable}
  defp fact(label, value) when is_binary(value), do: %{label: label, value: value}
  defp fact(label, value), do: %{label: label, value: to_string(value)}

  defp environment do
    Application.get_env(:bilimbi_base_ui, :environment) || Application.get_env(:web, :environment) ||
      "dev"
  end

  defp debug?, do: environment() not in ["prod", "production", :prod]

  defp endpoint_url do
    case Application.get_env(:web, BilimbiWeb.Endpoint) do
      nil ->
        :unavailable

      config ->
        case config[:url] do
          nil -> :unavailable
          url -> "#{url[:scheme] || "http"}://#{url[:host] || "localhost"}"
        end
    end
  end

  # Exercised rather than inferred: config being present says nothing about
  # whether the database is reachable right now.
  defp connection_status do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> "Connected"
      {:error, _reason} -> "Unreachable"
    end
  rescue
    _error -> "Unreachable"
  catch
    :exit, _reason -> "Unreachable"
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _other -> :unavailable
    end
  end

  # `:disksup` comes from `:os_mon`, declared in this module's `extra_applications`.
  # It is still reached through `apply/3` and guarded on the process being alive:
  # `:os_mon` is an optional OTP application that a trimmed release can exclude,
  # and a System Info page that crashes because it could not read a disk is worse
  # than one that says it could not read a disk.
  defp disk(which) do
    with true <- Process.whereis(:disksup) != nil,
         [_ | _] = data <- apply(:disksup, :get_disk_data, []),
         {_mount, total_kb, percent_used} <- root_partition(data) do
      case which do
        :total -> format_bytes(total_kb * 1024)
        :free -> format_bytes(trunc(total_kb * 1024 * (100 - percent_used) / 100))
      end
    else
      _other -> :unavailable
    end
  rescue
    _error -> :unavailable
  end

  defp root_partition(data) do
    Enum.find(data, fn {mount, _total, _percent} -> to_string(mount) == "/" end) ||
      List.first(data)
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    units = ["B", "KB", "MB", "GB", "TB"]

    {value, unit} =
      Enum.reduce_while(units, {bytes * 1.0, "B"}, fn unit, {value, _previous} ->
        if value < 1024.0, do: {:halt, {value, unit}}, else: {:cont, {value / 1024.0, unit}}
      end)

    "#{:erlang.float_to_binary(value, decimals: 1)} #{unit}"
  end

  defp format_bytes(_bytes), do: :unavailable
end
