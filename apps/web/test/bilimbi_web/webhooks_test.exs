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

  defp machine_conn(remote_ip \\ {127, 0, 0, 1}) do
    %{build_conn() | remote_ip: remote_ip}
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

  # Closes the open admission window, writing its aggregated refusal rows.
  defp close_window do
    send(WebhookRateLimit, :close)
    _ = :sys.get_state(WebhookRateLimit)
  end

  defp audit_payloads do
    "webhook.delivery" |> Bilimbi.Base.Audit.TestFixtures.action_payloads() |> List.flatten()
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

  test "actual byte size is bounded regardless of content length" do
    assert {:ok, _} = Settings.put("webhooks.max_bytes", 3)
    assert response(delivery("123"), 202)
    assert_received {:webhook_body, "123"}
    assert response(delivery("1234", [{"content-length", "1"}]), 403)
    refute_received {:webhook_body, "1234"}
  end

  test "a flood of unsigned requests does not refuse a genuine signed delivery" do
    assert {:ok, _} = Settings.put("webhooks.rate_limit", 1)
    assert {:ok, _} = Settings.put("webhooks.sender_rate_limit", 2)
    assert {:ok, _} = Settings.put("webhooks.failure_limit", 1)

    for host <- 1..10, _attempt <- 1..3 do
      conn = post(machine_conn({10, 0, 0, host}), "/webhooks/test-example", "{}")
      assert response(conn, 403)
    end

    assert response(delivery("{}"), 202)
    assert_received {:webhook_body, "{}"}
    assert response(delivery("{}"), 403)
    refute_received {:webhook_body, _}

    per_attempt = audit_payloads()
    close_window()
    aggregated = audit_payloads() -- per_attempt

    assert Enum.frequencies_by(per_attempt, & &1["reason"]) ==
             %{"verification_refused" => 1, "accepted" => 1}

    assert Enum.sort_by(aggregated, & &1["reason"]) == [
             %{
               "handler" => "test-example",
               "reason" => "rate_limited",
               "result" => "refused",
               "count" => 11
             },
             %{
               "handler" => "test-example",
               "reason" => "verification_refused",
               "result" => "refused",
               "count" => 19
             }
           ]
  end

  test "through a trusted proxy, forwarded clients get separate sender buckets" do
    assert {:ok, _} = Settings.put("webhooks.sender_rate_limit", 2)

    for _attempt <- 1..5 do
      conn =
        machine_conn()
        |> put_req_header("x-forwarded-for", "198.51.100.7")
        |> post("/webhooks/test-example", "{}")

      assert response(conn, 403)
    end

    assert response(delivery("{}", [{"x-forwarded-for", "203.0.113.20"}]), 202)
    assert_received {:webhook_body, "{}"}
  end

  test "a forwarded header from an untrusted peer is ignored" do
    assert {:ok, _} = Settings.put("webhooks.sender_rate_limit", 1)
    peer = {192, 0, 2, 9}

    first =
      machine_conn(peer)
      |> put_req_header("x-forwarded-for", "198.51.100.1")
      |> post("/webhooks/test-example", "{}")

    assert response(first, 403)

    body = "{}"
    signature = :crypto.mac(:hmac, :sha256, "test-only-key", body) |> Base.encode16(case: :lower)

    second =
      machine_conn(peer)
      |> put_req_header("x-forwarded-for", "198.51.100.2")
      |> put_req_header("x-signature", signature)
      |> post("/webhooks/test-example", body)

    assert response(second, 403)
    refute_received {:webhook_body, _}
  end

  test "a close with no open window leaves admission working" do
    close_window()
    close_window()
    assert response(delivery("{}"), 202)
    close_window()
    assert response(delivery("{}"), 202)
  end

  test "settings are read once per window" do
    assert response(delivery("{}"), 202)
    assert {:ok, _} = Settings.put("webhooks.rate_limit", 1)
    assert response(delivery("{}"), 202)
    close_window()
    assert response(delivery("{}"), 202)
    assert response(delivery("{}"), 403)
  end

  test "audit records accepted and refused deliveries without signature, body or callback data" do
    body = "secret body"
    assert response(delivery(body), 202)
    assert response(post(machine_conn(), "/webhooks/untrusted-name", body), 403)
    assert response(post(machine_conn(), "/webhooks/other-name", body), 403)
    assert [accepted] = audit_payloads()
    close_window()
    assert [^accepted, refused] = audit_payloads()

    assert accepted == %{
             "handler" => "test-example",
             "reason" => "accepted",
             "result" => "succeeded"
           }

    assert refused == %{
             "handler" => "unknown",
             "reason" => "unknown_handler",
             "result" => "refused",
             "count" => 2
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
    close_window()
    assert response(BilimbiWeb.Webhooks.deliver(conn, "test-example"), 403)
    refute_received {:webhook_body, _}
  end

  test "atomic limiter admits exactly the configured count under concurrent requests" do
    assert {:ok, _} = Settings.put("webhooks.sender_rate_limit", 5)

    results =
      1..40
      |> Task.async_stream(fn _ ->
        WebhookRateLimit.admit_sender("test-example", {127, 0, 0, 1})
      end)
      |> Enum.map(fn {:ok, value} -> value end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 5
  end
end
