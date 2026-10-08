defmodule Bilimbi.Core.Compatibility.BelimbingSchemaFixture do
  @moduledoc """
  Loads `test/fixtures/belimbing/schema.sql`, the schema-only dump of a
  database upstream Belimbing's own migrations created, into a database.

  The file is sent as one simple-protocol query, so the server splits the
  statements and dollar-quoted bodies need no client-side parsing. psql's
  `\\restrict` bracket is stripped when the file is generated; see
  `regenerate.sh` beside it.
  """

  @behaviour Postgrex.SimpleConnection

  alias Postgrex.SimpleConnection

  @path Path.expand("../fixtures/belimbing/schema.sql", __DIR__)
  @connection_keys [:hostname, :port, :username, :password, :database, :socket_dir, :ssl]

  @doc "The fixture file."
  def path, do: @path

  @doc "The upstream Belimbing commit the fixture header names."
  def source_commit do
    case Regex.run(~r/^-- belimbing-commit: ([0-9a-f]{40})$/m, File.read!(@path)) do
      [_line, commit] -> commit
      nil -> raise "#{@path} names no belimbing-commit in its header"
    end
  end

  @doc "Creates the fixture's structure in the database `repo_config` names."
  def load!(repo_config) when is_list(repo_config) do
    {:ok, pid} =
      SimpleConnection.start_link(__MODULE__, [], Keyword.take(repo_config, @connection_keys))

    try do
      case SimpleConnection.call(pid, {:query, File.read!(@path)}, 120_000) do
        results when is_list(results) -> :ok
        %Postgrex.Error{} = error -> raise error
      end
    after
      GenServer.stop(pid)
    end
  end

  @impl true
  def init(_args), do: {:ok, %{from: nil}}

  # The dump raises no notifications; the behaviour still requires the callback.
  @impl true
  def notify(_channel, _payload, _state), do: :ok

  @impl true
  def handle_call({:query, query}, from, state), do: {:query, query, %{state | from: from}}

  @impl true
  def handle_result(result, state) do
    SimpleConnection.reply(state.from, result)
    {:noreply, %{state | from: nil}}
  end
end
