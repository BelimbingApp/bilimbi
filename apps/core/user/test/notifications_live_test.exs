defmodule Bilimbi.Core.User.Web.NotificationsLiveTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.User.Web.NotificationsLive

  # Regression for #545. This LiveView used to resolve its own user id with
  # `user["user_id"] || user["id"] || user[:id] || 0`. The `|| 0` did not fail
  # on a malformed scope — it scoped every read to user 0, which does not
  # exist, so the page rendered as a legitimately empty notifications list. A
  # signed-in account with unread notifications saw silence. Mounting must
  # raise instead, so the broken route is reported rather than absorbed.

  defp socket(current_scope) do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_scope: current_scope},
      private: %{live_temp: %{}}
    }
  end

  defp assert_refuses(current_scope) do
    assert_raise ArgumentError, ~r/carries no "user_id"/, fn ->
      NotificationsLive.mount(%{}, %{}, socket(current_scope))
    end
  end

  describe "mount/3 with a malformed scope" do
    test "refuses a scope whose user carries no id at all" do
      assert_refuses(%{user: %{}, scope: :unreachable})
    end

    test "refuses a scope carrying only a name" do
      assert_refuses(%{user: %{"name" => "Ada"}, scope: :unreachable})
    end

    test "refuses a nil user" do
      assert_refuses(%{user: nil, scope: :unreachable})
    end

    # The three keys the old fallback chain accepted. `presentation_user/2` is
    # the sole builder of this map and only ever writes "user_id", so a scope
    # arriving with "id" or :id is malformed, not an alternative spelling —
    # accepting it would silently resume the behaviour this test pins.
    test "refuses the alternate id spellings the old fallback chain accepted" do
      assert_refuses(%{user: %{"id" => 7}, scope: :unreachable})
      assert_refuses(%{user: %{id: 7}, scope: :unreachable})
    end
  end
end
