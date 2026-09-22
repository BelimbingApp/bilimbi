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

  attr(:value, :any, required: true)

  @doc """
  One fact's value inside the shared `<.list>`.

  `:unavailable` renders as "Unavailable" in muted text rather than being
  hidden, so a probe that could not answer is visibly different from a fact
  that happens to be empty.
  """
  def fact_value(%{value: :unavailable} = assigns) do
    ~H"""
    <span class="text-ink-faint">Unavailable</span>
    """
  end

  def fact_value(assigns) do
    ~H"""
    <span class="font-medium">{@value}</span>
    """
  end

  @doc "The stable row id for a fact label, so a test or an anchor can reach one row."
  def fact_id(card, label), do: "system-info-#{card}-#{slug(label)}"

  defp slug(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
