defmodule Bilimbi.Base.UI.RouteContractTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.RouteContract
  alias Bilimbi.Base.UI.RoutePatterns

  describe "RoutePatterns.match_path?/2" do
    test "matches parameterized user paths" do
      assert RoutePatterns.match_path?("/users/:id", ["users", "42"])
      refute RoutePatterns.match_path?("/users/:id", ["users"])
      refute RoutePatterns.match_path?("/users/:id", ["users", "42", "edit"])
    end

    test "matches the root path" do
      assert RoutePatterns.match_path?("/", [])
      refute RoutePatterns.match_path?("/", ["dashboard"])
    end

    test "matches reset-password token paths" do
      assert RoutePatterns.match_path?("/reset-password/:token", ["reset-password", "abc"])
      refute RoutePatterns.match_path?("/reset-password/:token", ["reset-password"])
    end
  end

  test "implements Phoenix.VerifiedRoutes callbacks" do
    assert Phoenix.VerifiedRoutes in Keyword.get(RouteContract.__info__(:attributes), :behaviour)
    assert function_exported?(RouteContract, :formatted_routes, 1)
    assert function_exported?(RouteContract, :verified_route?, 2)
  end

  test "verified_route? matches host routes compiled from the manifest" do
    assert RouteContract.verified_route?([], [])
    assert RouteContract.verified_route?([], ["users", "1"])
    assert RouteContract.verified_route?([], ["reset-password", "tok"])
    refute RouteContract.verified_route?([], ["no-such-route"])
  end
end

defmodule Bilimbi.Base.UI.VerifiedRoutesTest do
  use ExUnit.Case, async: true
  use Bilimbi.Base.UI, :html

  test "generates a verified host path without the web endpoint" do
    assert ~p"/dashboard" == "/dashboard"
    assert ~p"/users/#{1}" == "/users/1"
  end
end
