defmodule Bilimbi.Base.Artifacts.PDFTokensTest do
  use ExUnit.Case, async: false
  alias Bilimbi.Base.Artifacts.PDF.Tokens

  test "opaque signed tokens are single use; tampering cannot consume the original" do
    assert {:ok, token} = Tokens.issue(%{private: "secret"}, 60, 100)
    assert {:error, :not_found} = Tokens.consume(token <> "x")
    assert {:error, :not_found} = Tokens.consume(String.duplicate("a", 129))
    assert {:ok, %{private: "secret"}} = Tokens.consume(token)
    assert {:error, :not_found} = Tokens.consume(token)
  end

  test "concurrent consumers have exactly one winner" do
    {:ok, token} = Tokens.issue(%{private: "secret"}, 60, 100)
    results = 1..12 |> Task.async_stream(fn _ -> Tokens.consume(token) end) |> Enum.to_list()
    assert Enum.count(results, &(&1 == {:ok, {:ok, %{private: "secret"}}})) == 1
    assert Enum.count(results, &(&1 == {:ok, {:error, :not_found}})) == 11
  end

  test "revocation frees bounded capacity" do
    {:ok, token} = Tokens.issue(%{}, 60, 1)
    assert {:error, :render_tokens_full} = Tokens.issue(%{}, 60, 1)
    assert :ok = Tokens.revoke(token)
    assert {:error, :not_found} = Tokens.consume(token)
    {:ok, next} = Tokens.issue(%{}, 60, 1)
    Tokens.revoke(next)
  end

  test "expiry removes sensitive claims without needing a consume" do
    {:ok, token} = Tokens.issue(%{private: "secret"}, 1, 100)
    # A timer message to the same server after expiry is handled after its
    # scheduled deletion; acknowledge through a call, without sleeping.
    ref = make_ref()
    Process.send_after(self(), ref, 1100)
    assert_receive ^ref, 2000
    assert {:error, :not_found} = Tokens.consume(token)
  end
end
