defmodule BilimbiWeb.WebhookController do
  use BilimbiWeb, :controller

  def create(conn, %{"identifier" => identifier}),
    do: BilimbiWeb.Webhooks.deliver(conn, identifier)
end
