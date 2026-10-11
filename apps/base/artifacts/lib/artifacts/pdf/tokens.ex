defmodule Bilimbi.Base.Artifacts.PDF.Tokens do
  @moduledoc false
  use GenServer

  # Signed, random, single-use capabilities. Claims stay in this node's memory;
  # one serialized pop prevents concurrent replay. No template or actor ID is
  # accepted from HTTP. Expiry timers discard sensitive claims even with no traffic.
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def issue(claims, ttl, limit)
      when is_integer(ttl) and ttl > 0 and is_integer(limit) and limit > 0,
      do: GenServer.call(__MODULE__, {:issue, claims, ttl, limit})

  def consume(token) when is_binary(token) and byte_size(token) <= 128,
    do: GenServer.call(__MODULE__, {:consume, token})

  def consume(_), do: {:error, :not_found}
  def revoke(token), do: GenServer.call(__MODULE__, {:revoke, token})

  @impl true
  def init(_), do: {:ok, %{secret: :crypto.strong_rand_bytes(32), claims: %{}}}

  @impl true
  def handle_call({:issue, claims, ttl, limit}, _from, state) do
    if map_size(state.claims) >= limit do
      {:reply, {:error, :render_tokens_full}, state}
    else
      id = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      token = id <> "." <> sign(state.secret, id)
      timer = Process.send_after(self(), {:expire, token}, ttl * 1000)
      entry = {System.monotonic_time(:millisecond) + ttl * 1000, claims, timer}
      {:reply, {:ok, token}, %{state | claims: Map.put(state.claims, token, entry)}}
    end
  end

  def handle_call({:consume, token}, _from, state) do
    {entry, claims} = pop_verified(state, token)

    result =
      case entry do
        {expiry, value, timer} ->
          Process.cancel_timer(timer)

          if System.monotonic_time(:millisecond) < expiry,
            do: {:ok, value},
            else: {:error, :not_found}

        nil ->
          {:error, :not_found}
      end

    {:reply, result, %{state | claims: claims}}
  end

  def handle_call({:revoke, token}, _from, state) do
    {entry, claims} = pop_verified(state, token)
    if entry, do: Process.cancel_timer(elem(entry, 2))
    {:reply, :ok, %{state | claims: claims}}
  end

  defp pop_verified(state, token) do
    if verified?(state.secret, token),
      do: Map.pop(state.claims, token),
      else: {nil, state.claims}
  end

  defp verified?(secret, token) when is_binary(token) do
    case String.split(token, ".") do
      [id, signature] ->
        expected = sign(secret, id)
        byte_size(signature) == byte_size(expected) and :crypto.hash_equals(expected, signature)

      _ ->
        false
    end
  end

  defp verified?(_secret, _token), do: false

  defp sign(secret, id),
    do: :crypto.mac(:hmac, :sha256, secret, id) |> Base.url_encode64(padding: false)

  @impl true
  def handle_info({:expire, token}, state),
    do: {:noreply, %{state | claims: Map.delete(state.claims, token)}}

  @impl true
  def format_status(status),
    do: Map.merge(status, %{state: :redacted, message: :redacted, log: []})
end
