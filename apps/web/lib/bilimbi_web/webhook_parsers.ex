defmodule BilimbiWeb.WebhookParsers do
  @moduledoc """
  Leaves the reserved webhook namespace unread. Its controller reads bounded
  raw bytes before any decoding, for every content type. Machine API and OAuth
  endpoints accept JSON and URL-encoded objects, never multipart uploads: agent
  files stay in the harness. Browser forms retain their normal parsers and CSRF.
  """
  @behaviour Plug
  def init(opts) do
    machine_parsers = Enum.filter(Keyword.fetch!(opts, :parsers), &(&1 in [:urlencoded, :json]))

    %{
      browser: Plug.Parsers.init(opts),
      machine: Plug.Parsers.init(Keyword.merge(opts, parsers: machine_parsers, pass: []))
    }
  end

  def call(%Plug.Conn{path_info: ["webhooks" | _]} = conn, _opts), do: conn
  def call(%Plug.Conn{path_info: ["api", "v1" | _]} = conn, opts), do: parse(conn, opts.machine)

  def call(%Plug.Conn{path_info: ["oauth", action]} = conn, opts)
      when action in ["device_authorization", "token"], do: parse(conn, opts.machine)

  def call(conn, opts), do: parse(conn, opts.browser)

  defp parse(conn, opts) do
    Plug.Parsers.call(conn, opts)
  rescue
    error ->
      # Preserve the accumulated conn, including the incoming exchange hook,
      # when decoding fails before Router wraps controller errors. Otherwise
      # Endpoint renders from its original conn and malformed API calls vanish.
      Plug.Conn.WrapperError.reraise(conn, :error, error, __STACKTRACE__)
  end
end
