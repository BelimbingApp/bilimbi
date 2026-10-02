defmodule BilimbiWeb.ForwardedFor do
  @moduledoc """
  Sets `remote_ip` to the client address a trusted reverse proxy reports.

  Only when the direct peer is in the trusted-proxy list is `X-Forwarded-For`
  read, right to left, skipping trusted hops; the first untrusted address is
  the client. A header from an untrusted peer, or one with an unparseable hop
  before an untrusted address is found, leaves `remote_ip` unchanged.

  The list is `:web, :trusted_proxies`, set at boot from the comma-separated
  `TRUSTED_PROXIES` CIDRs, and defaults to loopback.
  """
  @behaviour Plug
  import Bitwise

  def init(opts), do: opts

  def call(conn, _opts) do
    proxies = Application.get_env(:web, :trusted_proxies, default())

    with true <- trusted?(conn.remote_ip, proxies),
         {:ok, client} <- client(conn, proxies) do
      %{conn | remote_ip: client}
    else
      _ -> conn
    end
  end

  def parse!(cidrs) do
    cidrs
    |> String.split(",", trim: true)
    |> Enum.map(fn cidr ->
      [address | prefix] = cidr |> String.trim() |> String.split("/", parts: 2)
      {:ok, address} = address |> String.to_charlist() |> :inet.parse_strict_address()
      bits = if tuple_size(address) == 4, do: 32, else: 128
      prefix = if prefix == [], do: bits, else: String.to_integer(hd(prefix))
      true = prefix in 0..bits
      {to_integer(address), bits, prefix}
    end)
  end

  defp default, do: parse!("127.0.0.0/8,::1/128")

  defp client(conn, proxies) do
    conn
    |> Plug.Conn.get_req_header("x-forwarded-for")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.reverse()
    |> Enum.reduce_while(:error, fn hop, :error ->
      case hop |> String.trim() |> String.to_charlist() |> :inet.parse_strict_address() do
        {:ok, address} ->
          if trusted?(address, proxies), do: {:cont, :error}, else: {:halt, {:ok, address}}

        {:error, _} ->
          {:halt, :error}
      end
    end)
  end

  defp trusted?(address, proxies) when is_tuple(address) do
    address = unmap(address)
    bits = if tuple_size(address) == 4, do: 32, else: 128
    value = to_integer(address)

    Enum.any?(proxies, fn {network, network_bits, prefix} ->
      network_bits == bits and value >>> (bits - prefix) == network >>> (bits - prefix)
    end)
  end

  defp trusted?(_address, _proxies), do: false

  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp unmap(address), do: address

  defp to_integer(address) do
    width = if tuple_size(address) == 4, do: 8, else: 16
    address |> Tuple.to_list() |> Enum.reduce(0, &(&2 <<< width ||| &1))
  end
end
