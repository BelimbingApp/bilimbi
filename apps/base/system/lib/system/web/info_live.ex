defmodule Bilimbi.Base.System.Web.InfoLive do
  @moduledoc """
  System Info: application, runtime, database, host, health and loaded applications.

  Every value is read at mount. Nothing here polls -- these facts change on
  deploy or not at all, and Belimbi's source screen does not refresh either.
  """

  use Bilimbi.Base.UI, :live_view

  alias Bilimbi.Base.System

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "System Info")
     |> assign(:active_nav, "admin.system.info")
     |> assign(:application_facts, System.application())
     |> assign(:runtime_facts, System.runtime())
     |> assign(:database_facts, System.database())
     |> assign(:server_facts, System.server())
     |> assign(:health_facts, System.health())
     |> assign(:applications, System.applications())}
  end

  attr(:id, :string, required: true)
  attr(:facts, :list, required: true)

  @doc """
  A card's rows.

  `:unavailable` renders as "Unavailable" in muted text rather than being
  hidden, so a probe that could not answer is visibly different from a fact
  that happens to be empty.
  """
  def fact_list(assigns) do
    ~H"""
    <dl id={"system-info-#{@id}-facts"} class="divide-y divide-line-subtle text-sm">
      <div
        :for={fact <- @facts}
        id={"system-info-#{@id}-#{slug(fact.label)}"}
        class="flex items-baseline justify-between gap-3 px-2 py-1.5"
      >
        <dt class="text-ink-muted">{fact.label}</dt>
        <dd :if={fact.value == :unavailable} class="text-right text-ink-faint">Unavailable</dd>
        <dd :if={fact.value != :unavailable} class="text-right font-medium text-ink">
          {fact.value}
        </dd>
      </div>
    </dl>
    """
  end

  defp slug(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
