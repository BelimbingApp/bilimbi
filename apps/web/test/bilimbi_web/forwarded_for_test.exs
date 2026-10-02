defmodule BilimbiWeb.ForwardedForTest do
  use ExUnit.Case, async: false
  alias BilimbiWeb.ForwardedFor

  defp client(peer, forwarded) do
    conn = %{Plug.Test.conn(:get, "/") | remote_ip: peer}

    conn =
      Enum.reduce(forwarded, conn, &Plug.Conn.prepend_req_headers(&2, [{"x-forwarded-for", &1}]))

    ForwardedFor.call(conn, ForwardedFor.init([])).remote_ip
  end

  test "a loopback proxy reports the right-most untrusted hop" do
    assert client({127, 0, 0, 1}, ["203.0.113.1, 198.51.100.2, 127.0.0.1"]) ==
             {198, 51, 100, 2}

    assert client({0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}, ["198.51.100.3"]) == {198, 51, 100, 3}
    assert client({0, 0, 0, 0, 0, 0, 0, 1}, ["2001:db8::5"]) == {8193, 3512, 0, 0, 0, 0, 0, 5}
  end

  test "an untrusted peer, a malformed hop or no header leaves the peer address" do
    assert client({192, 0, 2, 9}, ["198.51.100.2"]) == {192, 0, 2, 9}
    assert client({127, 0, 0, 1}, ["198.51.100.2, not-an-ip"]) == {127, 0, 0, 1}
    assert client({127, 0, 0, 1}, []) == {127, 0, 0, 1}
  end

  test "configured proxies replace the loopback default" do
    previous = Application.fetch_env(:web, :trusted_proxies)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:web, :trusted_proxies, value)
        :error -> Application.delete_env(:web, :trusted_proxies)
      end
    end)

    Application.put_env(:web, :trusted_proxies, ForwardedFor.parse!("10.0.0.0/8"))
    assert client({10, 1, 2, 3}, ["198.51.100.2, 10.9.9.9"]) == {198, 51, 100, 2}
    assert client({127, 0, 0, 1}, ["198.51.100.2"]) == {127, 0, 0, 1}
  end
end
