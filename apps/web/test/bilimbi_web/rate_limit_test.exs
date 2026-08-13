defmodule BilimbiWeb.RateLimitTest do
  use ExUnit.Case, async: false

  alias BilimbiWeb.RateLimit

  # Belimbing's contract: five attempts per key inside a 60-second decay,
  # then a lockout that reports the remaining seconds; success clears it.
  # Tests use a short window rather than sleeping.

  test "allows up to the limit, then denies with a retry hint" do
    key = {:test, System.unique_integer()}

    for _ <- 1..5 do
      assert :allow = RateLimit.attempt_allowed?(key)
      :ok = RateLimit.record_attempt(key, 60_000)
    end

    assert {:deny, seconds} = RateLimit.attempt_allowed?(key)
    assert seconds in 1..60
  end

  test "reset clears the lockout" do
    key = {:test, System.unique_integer()}

    for _ <- 1..5, do: RateLimit.record_attempt(key, 60_000)
    assert {:deny, _} = RateLimit.attempt_allowed?(key)

    :ok = RateLimit.reset(key)
    assert :allow = RateLimit.attempt_allowed?(key)
  end

  test "attempts outside the window no longer count" do
    key = {:test, System.unique_integer()}

    for _ <- 1..5, do: RateLimit.record_attempt(key, 0)

    assert :allow = RateLimit.attempt_allowed?(key)
  end

  test "keys are independent" do
    key_a = {:test, System.unique_integer()}
    key_b = {:test, System.unique_integer()}

    for _ <- 1..5, do: RateLimit.record_attempt(key_a, 60_000)

    assert {:deny, _} = RateLimit.attempt_allowed?(key_a)
    assert :allow = RateLimit.attempt_allowed?(key_b)
  end
end
