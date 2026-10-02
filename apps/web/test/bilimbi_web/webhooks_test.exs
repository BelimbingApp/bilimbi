defmodule BilimbiWeb.WebhooksTest do
  use BilimbiWeb.ConnCase, async: false
  alias Bilimbi.Base.Settings
  alias BilimbiWeb.WebhookRateLimit

  setup do
    # Restart only this supervised, test-local limiter, not infrastructure.
    Supervisor.terminate_child(BilimbiWeb.Supervisor, WebhookRateLimit)
    Supervisor.restart_child(BilimbiWeb.Supervisor, WebhookRateLimit)
    :ok
  end

  defp machine_conn do
    build_conn()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("content-type", "application/json")
  end

  defp delivery(body, headers \\ []) do
    signature = :crypto.mac(:hmac, :sha256, "test-only-key", body) |> Base.encode16(case: :lower)

    conn =
      machine_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-signature", signature)

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    post(conn, "/webhooks/test-example", body)
  end

  test "endpoint preserves exact JSON bytes, bypasses CSRF and does not decode" do
    body = " {\n \"b\":2, \"a\":1 } \n"
    assert response(delivery(body), 202) == ~s({"status":"accepted"})
    assert_received {:webhook_body, ^body}
    # Invalid JSON and non-UTF8 are valid signature inputs at the host boundary.
    bytes = <<255, 0, 1, 123>>
    assert response(delivery(bytes), 202)
    assert_received {:webhook_body, ^bytes}
  end

  test "ordinary browser POST still enforces CSRF" do
    conn = machine_conn() |> put_req_header("content-type", "application/json")
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn -> post(conn, "/session", "{}") end
  end

  test "unknown identifiers, invalid signatures and handler failures refuse uniformly" do
    unknown = post(machine_conn(), "/webhooks/unknown", "{}")

    bad =
      post(
        machine_conn() |> put_req_header("content-type", "application/json"),
        "/webhooks/test-example",
        "{}"
      )

    refused = delivery("{}", [{"x-test-outcome", "refuse"}])
    raised = delivery("{}", [{"x-test-outcome", "raise"}])

    for conn <- [unknown, bad, refused, raised] do
      assert response(conn, 403) == ~s({"error":"delivery_refused"})
    end

    refute_received {:webhook_body, _}
  end

  test "actual byte size is bounded regardless of content length and setting changes apply immediately" do
    assert {:ok, _} = Settings.put("webhooks.max_bytes", 3)
    assert response(delivery("123"), 202)
    assert_received {:webhook_body, "123"}
    assert response(delivery("1234", [{"content-length", "1"}]), 403)
    refute_received {:webhook_body, "1234"}
  end

  test "refusals consume the same atomic per-handler rate window" do
    assert {:ok, _} = Settings.put("webhooks.rate_limit", 1)
    bad = post(machine_conn(), "/webhooks/test-example", "{}")
    assert response(bad, 403)
    assert response(delivery("{}"), 403)
    refute_received {:webhook_body, _}
  end

  test "audit records accepted and refused deliveries without signature, body or callback data" do
    body = "secret body"
    assert response(delivery(body), 202)
    assert response(post(machine_conn(), "/webhooks/untrusted-name", body), 403)
    rows = Bilimbi.Base.Audit.TestFixtures.action_payloads("webhook.delivery")
    assert [[accepted], [refused]] = rows

    assert accepted == %{
             "handler" => "test-example",
             "reason" => "accepted",
             "result" => "succeeded"
           }

    assert refused == %{
             "handler" => "unknown",
             "reason" => "unknown_handler",
             "result" => "refused"
           }
  end

  test "raw preservation covers arbitrary content types" do
    conn =
      Plug.Test.conn(:post, "/webhooks/test-example", "a=b&c=%FF")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    parsed =
      BilimbiWeb.WebhookParsers.call(
        conn,
        BilimbiWeb.WebhookParsers.init(parsers: [:urlencoded], pass: ["*/*"])
      )

    assert %Plug.Conn.Unfetched{} = parsed.body_params
    assert {:ok, "a=b&c=%FF", _} = Plug.Conn.read_body(parsed)
  end

  test "chunked reads concatenate exact bytes and enforce the aggregate limit" do
    body = "12345"
    signature = :crypto.mac(:hmac, :sha256, "test-only-key", body) |> Base.encode16(case: :lower)

    conn =
      Plug.Test.conn(:post, "/webhooks/test-example", body)
      |> put_req_header("x-signature", signature)

    {_, state} = conn.adapter
    conn = %{conn | adapter: {BilimbiWeb.WebhookChunkAdapter, state}}
    assert response(BilimbiWeb.Webhooks.deliver(conn, "test-example"), 202)
    assert_received {:webhook_body, ^body}
    assert {:ok, _} = Settings.put("webhooks.max_bytes", 4)
    assert response(BilimbiWeb.Webhooks.deliver(conn, "test-example"), 403)
    refute_received {:webhook_body, _}
  end

  test "atomic limiter admits exactly the configured count under concurrent requests" do
    results =
      1..40
      |> Task.async_stream(fn _ -> WebhookRateLimit.admit("test-example", 5, 60_000) end)
      |> Enum.map(fn {:ok, value} -> value end)

    assert Enum.count(results, &(&1 == :ok)) == 5
  end
end
