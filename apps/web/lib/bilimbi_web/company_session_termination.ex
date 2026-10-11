defmodule BilimbiWeb.CompanySessionTermination do
  @moduledoc """
  Ends an archived company's sessions as soon as the archive commits.

  An archived company's accounts cannot sign in or keep a session: the login
  edge refuses them on every request and LiveView event
  (`Bilimbi.Core.Company.fetch_tenant_id_for_company/1`). This process is the
  host's subscriber to Core Company's committed lifecycle facts. On
  `archive` it asks Core User to end every durable session of the company's
  accounts, and `BilimbiWeb.SessionDisconnect` then closes their open tabs
  instead of waiting for their next action.

  The refusal does not depend on this message arriving; this only makes it
  immediate. Sign-in is not stored as blocked anywhere, so it follows the
  company's status if that ever changes back.
  """

  use GenServer

  require Logger

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case Company.subscribe_lifecycle() do
      :ok -> {:ok, %{}}
      {:error, reason} -> {:stop, {:company_lifecycle_unavailable, reason}}
    end
  end

  @impl true
  def handle_info(
        {:company_lifecycle,
         %{operation: :archive, tenant_id: tenant_id, company_id: company_id}},
        state
      ) do
    with {:ok, scope} <- Tenancy.scope(tenant_id),
         {:ok, _count} <- User.terminate_company_sessions(scope, company_id) do
      :ok
    else
      {:error, reason} ->
        Logger.warning(
          "archived company #{company_id} sessions were not ended: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
