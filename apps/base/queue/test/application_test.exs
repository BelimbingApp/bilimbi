defmodule Bilimbi.Base.Queue.ApplicationTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.Application, as: QueueApplication

  test "production configuration defines a validated graceful shutdown policy" do
    config = Queue.oban_config() |> Keyword.delete(:testing)

    assert config[:repo] == Bilimbi.Base.Repo
    assert config[:name] == Bilimbi.Base.Queue.Oban
    assert config[:queues] == [default: 10]
    assert config[:plugins] == [{Oban.Plugins.Pruner, max_age: 604_800}]
    assert config[:shutdown_grace_period] == 15_000
    assert :ok = Oban.Config.validate(config)
    assert [{Oban, ^config}] = QueueApplication.children(config)
  end

  test "manual test mode starts no consumers or plugins automatically" do
    config = Queue.oban_config()

    assert config[:testing] == :manual
    assert [] = QueueApplication.children(config)

    normalized = Oban.Config.new(config)
    assert normalized.queues == []
    assert normalized.plugins == []
    assert normalized.stage_interval == :infinity
  end
end
