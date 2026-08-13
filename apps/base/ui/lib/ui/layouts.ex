defmodule Bilimbi.Base.UI.Layouts do
  @moduledoc """
  Shared Bilimbi web shells and feedback surfaces.

  Two shells:

    * `auth/1` — the centered credential layout (login and, later, password
      reset). Compact card on the warm canvas with the Bilimbi brand bar;
      the page is otherwise quiet so the form reads first.
    * `app/1` — the authenticated workspace shell: a compact sidebar with
      primary navigation and the signed-in user footer, plus a top strip
      that always names the workspace (tenant) the screen acts on.

  The workspace strip is a deliberate Bilimbi distinction from Belimbing:
  no authenticated screen is context-free.
  """

  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Bilimbi.Base.UI.Components

  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    router: Bilimbi.Base.UI.RouteContract,
    endpoint: Bilimbi.Base.UI.ScriptPath,
    statics: ~w(assets fonts images favicon.ico robots.txt)

  embed_templates("layouts/*")

  @doc """
  The centered credential layout. Renders its own flash group because the
  workspace shell is absent here.
  """
  attr(:flash, :map, required: true)
  slot(:inner_block, required: true)

  def auth(assigns) do
    ~H"""
    <div class="flex min-h-svh flex-col items-center justify-center gap-6 p-6">
      <div class="flex w-full max-w-sm flex-col gap-5">
        <.link navigate={~p"/"} class="flex flex-col items-center gap-2.5" aria-label="Bilimbi home">
          <span class="grid size-10 place-items-center rounded-xl bg-brand shadow-sm shadow-brand-ink/10">
            <img
              src={~p"/images/logo.svg"}
              alt=""
              class="size-6 object-contain"
              width="24"
              height="24"
              decoding="async"
              loading="eager"
              aria-hidden="true"
            />
          </span>
          <span class="text-base font-semibold tracking-tight text-ink-strong">Bilimbi</span>
        </.link>

        <div
          id="auth-card"
          class="rounded-xl border border-line bg-surface shadow-sm shadow-ink/[0.04]"
        >
          <div class="h-0.5 rounded-t-xl bg-brand" aria-hidden="true"></div>
          <div class="px-7 py-6 sm:px-8">{render_slot(@inner_block)}</div>
        </div>

        <p class="text-center text-xs text-ink-faint">
          Business application platform
        </p>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The authenticated workspace shell. Requires `@current_scope` — routes must
  run through the authenticated pipeline rather than tolerating a fallback.
  """
  attr(:flash, :map, required: true)
  attr(:current_scope, :map, required: true)
  attr(:active_nav, :string, default: nil)
  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-canvas">
      <aside
        id="app-sidebar"
        class="flex w-14 shrink-0 flex-col border-r border-line bg-surface lg:w-60"
      >
        <.link
          navigate={~p"/dashboard"}
          id="app-brand"
          class="flex items-center justify-center gap-2.5 border-b border-line-subtle px-2 py-3.5 lg:justify-start lg:px-4"
          aria-label="Bilimbi dashboard"
        >
          <span class="grid size-8 shrink-0 place-items-center rounded-lg bg-brand">
            <img
              src={~p"/images/logo.svg"}
              alt=""
              class="size-5 object-contain"
              width="20"
              height="20"
              decoding="async"
              loading="eager"
              aria-hidden="true"
            />
          </span>
          <span class="hidden text-sm font-semibold tracking-tight text-ink-strong lg:inline">
            Bilimbi
          </span>
        </.link>

        <nav
          id="app-nav"
          aria-label="Main navigation"
          class="flex-1 overflow-y-auto px-1.5 py-3 lg:px-2"
        >
          <p class="hidden px-2 pb-1 text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint select-none lg:block">
            Workspace
          </p>
          <.nav_branch
            :for={node <- Bilimbi.Base.UI.Nav.tree(@current_scope)}
            node={node}
            active_nav={@active_nav}
            depth={0}
          />
        </nav>

        <div id="app-user" class="border-t border-line-subtle px-1.5 py-3 lg:px-3">
          <div class="flex flex-col items-center gap-1.5 lg:flex-row lg:gap-2.5">
            <span class="grid size-8 shrink-0 place-items-center rounded-full bg-action text-xs font-semibold text-action-ink">
              {user_initials(@current_scope.user["name"])}
            </span>
            <div class="hidden min-w-0 flex-1 lg:block">
              <p id="app-user-name" class="truncate text-sm font-medium text-ink">
                {@current_scope.user["name"]}
              </p>
              <p class="truncate text-xs text-ink-subtle">{@current_scope.user["email"]}</p>
            </div>
            <.link
              href={~p"/session"}
              method="delete"
              id="app-logout"
              class="grid size-7 shrink-0 place-items-center rounded-md text-ink-subtle transition hover:bg-surface-sunken hover:text-ink"
              aria-label="Log out"
              title="Log out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
            </.link>
          </div>
        </div>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <header
          id="app-topbar"
          class="flex h-12 shrink-0 items-center justify-between border-b border-line bg-surface px-5"
        >
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint">
            {@current_scope.user["company_name"] || "Workspace"}
          </p>
          <p
            id="app-tenant"
            class="flex items-center gap-1.5 text-xs text-ink-subtle"
            title="Every screen in this shell acts on this tenant"
          >
            <.icon name="hero-identification" class="size-3.5" /> Tenant
            <span class="tabular-nums font-medium text-ink-muted">
              {@current_scope.scope.tenant.id}
            </span>
            <span :if={@current_scope.scope.tenant.is_platform_operator} class="text-ink-faint">
              · platform operator
            </span>
          </p>
        </header>

        <main id="app-content" class="min-h-0 flex-1 overflow-y-auto px-5 py-6 sm:px-8">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr(:navigate, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:active, :boolean, default: false)
  attr(:id, :string, required: true)
  slot(:inner_block, required: true)

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      aria-current={@active && "page"}
      class={[
        "relative flex items-center justify-center gap-2.5 rounded-md px-2 py-2 text-sm transition lg:justify-start lg:py-1.5",
        @active && "bg-surface-sunken font-medium text-ink-strong",
        !@active && "text-ink-muted hover:bg-surface-sunken hover:text-ink"
      ]}
    >
      <span
        :if={@active}
        class="absolute inset-y-1 left-0 w-0.5 rounded-full bg-brand-strong"
        aria-hidden="true"
      ></span>
      <.icon name={@icon} class={["size-4 shrink-0", @active && "text-brand-strong"]} />
      <span class="hidden truncate lg:inline">{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  attr(:node, :map, required: true)
  attr(:active_nav, :string, default: nil)
  attr(:depth, :integer, default: 0)

  defp nav_branch(assigns) do
    ~H"""
    <.nav_item
      :if={@node.item.route}
      navigate={@node.item.route}
      icon={nav_icon(@node.item.icon)}
      active={@active_nav == @node.item.id}
      id={"nav-" <> String.replace(@node.item.id, ".", "-")}
    >
      {@node.item.label}
    </.nav_item>

    <p
      :if={is_nil(@node.item.route) and @node.children != []}
      class="hidden px-2 pt-3 pb-1 text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint select-none lg:block"
    >
      {@node.item.label}
    </p>

    <.nav_branch
      :for={child <- @node.children}
      node={child}
      active_nav={@active_nav}
      depth={@depth + 1}
    />
    """
  end

  # Menu contributions carry bare Heroicon names so a module never encodes the
  # host's icon-set prefix. A fully qualified name is passed through unchanged.
  defp nav_icon(nil), do: "hero-square-3-stack-3d"
  defp nav_icon("hero-" <> _ = name), do: name
  defp nav_icon(name) when is_binary(name), do: "hero-" <> name

  defp user_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp user_initials(_), do: "?"

  attr(:flash, :map, required: true)
  attr(:id, :string, default: "flash-group")

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
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 animate-spin" />
      </.flash>
    </div>
    """
  end
end
