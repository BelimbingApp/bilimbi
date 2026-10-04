defmodule Bilimbi.Core.User.Web.NotificationsLiveTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.User.Web.NotificationsLive

  # Regression for #545. This LiveView used to resolve its own user id with
  # `user["user_id"] || user["id"] || user[:id] || 0`. The `|| 0` did not fail
  # on a malformed scope — it scoped every read to user 0, which does not
  # exist, so the page rendered as a legitimately empty notifications list.
  # The subject is now the sealed tenancy scope. A current_scope that does not
  # carry one, including one that still names a user id on the map, must raise
  # rather than render that empty list.

  defp socket(current_scope) do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_scope: current_scope},
      private: %{live_temp: %{}}
    }
  end

  defp assert_refuses(current_scope) do
    assert_raise ArgumentError, ~r/tenancy scope/, fn ->
      NotificationsLive.mount(%{}, %{}, socket(current_scope))
    end
  end

  describe "mount/3 with a malformed scope" do
    test "refuses a current_scope that is not a tenancy scope" do
      for current_scope <- [
            %{user: %{}, scope: :unreachable},
            %{user: %{"name" => "Ada"}, scope: :unreachable},
            %{user: nil, scope: :unreachable},
            %{user: %{"id" => 7}, scope: :unreachable},
            %{user: %{id: 7}, scope: :unreachable},
            %{user: %{"user_id" => 91}, scope: :unreachable}
          ] do
        assert_refuses(current_scope)
      end
    end
  end
end
