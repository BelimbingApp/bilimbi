defmodule Bilimbi.Base.Settings.CacheTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Settings.Cache

  setup do
    unless Process.whereis(Cache), do: start_supervised!(Cache)
    Cache.clear()
    :ok
  end

  test "an invalidation prevents an in-flight load from republishing a row or miss" do
    for old <- [:old, nil] do
      key = {"race", "user", 1}
      parent = self()

      task =
        Task.async(fn ->
          Cache.fetch(key, fn ->
            send(parent, {:loaded, self()})

            receive do
              :publish -> old
            end
          end)
        end)

      assert_receive {:loaded, reader}
      Cache.invalidate("race", "user", 1)
      send(reader, :publish)
      assert Task.await(task) == old
      assert Cache.fetch(key, fn -> :new end) == :new
      Cache.clear()
    end
  end

  test "maintenance reclaims expired hits and misses without revisiting their keys" do
    Cache.fetch({"hit", nil, nil}, fn -> :value end)
    Cache.fetch({"miss", nil, nil}, fn -> nil end)
    Cache.fetch({"live", nil, nil}, fn -> :live end)

    :sys.replace_state(Cache, fn state ->
      for key <- ["hit", "miss"] do
        :ets.update_element(Cache, {key, nil, nil}, {2, System.monotonic_time(:millisecond) - 1})
      end

      state
    end)

    send(Process.whereis(Cache), :sweep)
    _ = :sys.get_state(Cache)

    assert :ets.info(Cache, :size) == 1
    assert Cache.fetch({"live", nil, nil}, fn -> flunk("live entry was removed") end) == :live
  end
end
