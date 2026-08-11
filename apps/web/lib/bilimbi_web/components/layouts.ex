defmodule BilimbiWeb.Layouts do
  @moduledoc """
  Shared Bilimbi web shell and feedback surfaces.
  """

  use BilimbiWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-full">
      <header id="app-header" class="border-b border-line/80 bg-surface/90 backdrop-blur">
        <div class="mx-auto flex h-16 max-w-6xl items-center justify-between px-5 sm:px-8">
          <a href={~p"/"} class="group flex items-center gap-3" aria-label="Bilimbi home">
            <span class="grid size-9 place-items-center rounded-xl bg-brand text-brand-ink shadow-sm shadow-brand-ink/10 transition-transform group-hover:-rotate-2 group-hover:scale-105">
              <.icon name="hero-squares-2x2" class="size-5" />
            </span>
            <span>
              <span class="block text-[0.68rem] font-semibold uppercase tracking-[0.2em] text-ink-subtle">
                Platform baseline
              </span>
              <span class="block text-sm font-semibold tracking-tight text-ink">Bilimbi</span>
            </span>
          </a>

          <div class="flex items-center gap-2 text-xs font-medium text-ink-subtle">
            <span class="size-2 rounded-full bg-success ring-4 ring-success/15"></span>
            Explicit tenancy read slice
          </div>
        </div>
      </header>

      <main id="app-content" class="mx-auto max-w-6xl px-5 py-10 sm:px-8 sm:py-16">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connection interrupted")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting…")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Server unavailable")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting…")}
      </.flash>
    </div>
    """
  end
end
