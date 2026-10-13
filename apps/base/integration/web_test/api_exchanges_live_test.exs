Code.ensure_loaded!(Bilimbi.Base.Integration.TestFixtures)

defmodule BilimbiWeb.ApiExchangesLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz.LiveAuthorization
  alias Bilimbi.Base.Integration
  alias Bilimbi.Base.Integration.TestFixtures, as: IntegrationFixtures
  alias Bilimbi.Base.Tenancy

  @list "admin.system.outbound-exchange.list"
  @delete "admin.system.outbound-exchange.delete"

  setup do
    signed_in_identity!()
    IntegrationFixtures.create_exchanges_table!()
    :ok
  end

  describe "list filters" do
    test "the direction tab, outcome and search narrow the rows", %{conn: conn} do
      grant_capabilities!(@list)
      scope = operator_scope()
      seed_exchanges!(scope)

      billing = exchange_id(scope, "outgoing", "invoice.create")
      payroll = exchange_id(scope, "outgoing", "payroll.run.submit")
      webhook = exchange_id(scope, "incoming", "webhook.receive")

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/api-exchanges")

      # Outgoing is the default tab.
      assert has_element?(view, "#exchange-#{billing}")
      assert has_element?(view, "#exchange-#{payroll}")
      refute has_element?(view, "#exchange-#{webhook}")

      view |> form("#exchange-filters", filters: %{"status" => "http_error"}) |> render_change()
      refute has_element?(view, "#exchange-#{billing}")
      assert has_element?(view, "#exchange-#{payroll}")

      view
      |> form("#exchange-filters", filters: %{"status" => "", "search" => "billing"})
      |> render_change()

      assert has_element?(view, "#exchange-#{billing}")
      refute has_element?(view, "#exchange-#{payroll}")

      view
      |> form("#exchange-filters", filters: %{"status" => "", "search" => ""})
      |> render_change()

      view |> element("#exchange-tabs a", "Incoming") |> render_click()
      assert has_element?(view, "#exchange-#{webhook}")
      refute has_element?(view, "#exchange-#{billing}")

      view
      |> form("#exchange-filters", filters: %{"search" => "zzz-no-such-host"})
      |> render_change()

      refute has_element?(view, "#exchange-#{webhook}")
      assert has_element?(view, "#exchanges", "No API exchanges")
    end
  end

  describe "delete on an exchange" do
    test "a reader without the delete capability sees no Delete, and a forged delete changes nothing",
         %{conn: conn} do
      grant_capabilities!(@list)
      scope = operator_scope()
      seed_exchanges!(scope)
      id = exchange_id(scope, "outgoing", "invoice.create")

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/api-exchanges/#{id}")

      refute has_element?(view, "#exchange-delete")
      assert has_element?(view, "#exchange-detail", "Deletion restricted")

      # The hidden button is absent, so send the event directly: the handler
      # must ask Authz again and refuse.
      assert render_click(view, "delete") =~ LiveAuthorization.denied_message()
      refute has_element?(view, "#exchange-delete-confirm")
      assert {:ok, %{id: ^id}} = Integration.get_exchange(scope, id)
    end

    test "a holder confirms the delete and the exchange is removed", %{conn: conn} do
      grant_capabilities!([@list, @delete])
      scope = operator_scope()
      seed_exchanges!(scope)
      id = exchange_id(scope, "outgoing", "invoice.create")

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/api-exchanges/#{id}")

      assert has_element?(view, "#exchange-delete")
      view |> element("#exchange-delete") |> render_click()
      assert has_element?(view, "#exchange-delete-confirm")

      assert {:error, {:live_redirect, %{to: "/system/api-exchanges"}}} =
               view |> element("#exchange-delete-confirm-confirm") |> render_click()

      assert {:error, :not_found} = Integration.get_exchange(scope, id)
    end
  end

  # The signed-in identity's sealed scope, built after its grants exist.
  defp operator_scope do
    {:ok, scope} = Tenancy.scope(41)
    Tenancy.Authentication.sign_in(scope, 91, 73)
  end

  defp seed_exchanges!(scope) do
    Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{}) end)

    {:ok, %{status: 200}} =
      Integration.request(
        scope,
        %{
          system: "billing",
          operation: "invoice.create",
          owner_type: "core/example",
          owner_id: 8
        },
        url: "https://billing.example.test/invoices",
        method: :post,
        json: %{},
        plug: {Req.Test, __MODULE__}
      )

    # POST is not retried by Req, so the 500 reaches the page once.
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
    end)

    {:ok, %{status: 500}} =
      Integration.request(
        scope,
        %{
          system: "payroll",
          operation: "payroll.run.submit",
          owner_type: "core/example",
          owner_id: 8
        },
        url: "https://payroll.example.test/runs",
        method: :post,
        json: %{},
        plug: {Req.Test, __MODULE__}
      )

    {:ok, _id} =
      Integration.record_incoming(scope, %{
        system: "partner",
        operation: "webhook.receive",
        endpoint: "/hooks/partner",
        method: :post,
        response_status: 202
      })

    :ok
  end

  defp exchange_id(scope, direction, operation) do
    {:ok, %{entries: entries}} = Integration.list_page(scope, direction: direction)
    %{id: id} = Enum.find(entries, &(&1.operation == operation))
    id
  end
end
