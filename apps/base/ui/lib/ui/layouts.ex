defmodule Bilimbi.Base.UI.Layouts do
  @moduledoc """
  Shared Bilimbi web shells and feedback surfaces.

  Two shells:

    * `auth/1` — the centered credential layout (login and, later, password
      reset). Compact card on the warm canvas with the Bilimbi brand bar;
      the page is otherwise quiet so the form reads first.
    * `app/1` — the authenticated workspace shell: a full-width top bar,
      a left menu rail, and a persistent status bar. The top bar names the
      tenant the screen acts on.

  No authenticated screen is context-free.
  """

  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Bilimbi.Base.UI.Components

  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    router: Bilimbi.Base.UI.RouteContract,
    endpoint: Bilimbi.Base.UI.ScriptPath,
    statics: ~w(assets fonts images favicon.ico favicon.svg robots.txt)

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
          <.brand_mark size={36} />
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
  # Required, not defaulted: a screen that forgets this renders a sidebar where
  # nothing is current, and the page still looks right. Two screens shipped
  # exactly that way before a reviewer caught it by reading, because a *missing*
  # attribute leaves nothing to grep for. Required makes it a compile error.
  # Pass nil deliberately for a page that owns no menu item.
  # `:any`, not `:string`: a page that owns no menu item must pass nil.
  # Forbidding a missing attribute is the guard; forbidding "none" is not.
  attr(:active_nav, :any, required: true)
  slot(:inner_block, required: true)

  def app(assigns) do
    nav = Bilimbi.Base.UI.Nav.tree(assigns.current_scope)

    assigns =
      assigns
      |> assign(:shell, shell_meta())
      |> assign(:nav, nav)

    ~H"""
    <div
      id="app-shell"
      phx-hook="AppShell"
      data-sidebar-mode="desktop"
      data-sidebar-rail="false"
      data-sidebar-open="false"
      class="flex h-screen flex-col overflow-hidden bg-canvas"
    >
      <header
        id="app-topbar"
        class="flex h-7 shrink-0 items-center justify-between gap-3 border-b border-line bg-surface px-3"
      >
        <button
          type="button"
          id="app-sidebar-toggle"
          class="inline-flex size-6 shrink-0 items-center justify-center rounded-sm text-action transition hover:bg-surface-sunken focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
          aria-label="Toggle sidebar"
          title="Toggle sidebar"
          aria-controls="app-sidebar"
          aria-expanded="false"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>

        <div id="app-topbar-main" class="flex min-w-0 flex-1 items-center justify-between gap-3">
          <.link
            navigate={~p"/dashboard"}
            id="app-brand"
            class="flex shrink-0 items-center gap-2 text-ink transition hover:opacity-90"
            aria-label="Bilimbi dashboard"
          >
            <.brand_mark size={24} />
            <span class="text-sm font-semibold tracking-tight text-ink-strong">Bilimbi</span>
          </.link>

          <p
            id="app-tenant"
            class="flex min-w-0 max-w-[50%] items-center gap-1.5 text-xs text-ink-subtle"
            title={"Every screen in this shell acts on tenant #{@current_scope.scope.tenant.name}"}
          >
            <.icon name="hero-identification" class="size-3.5 shrink-0" />
            <span class="hidden sm:inline">Tenant</span>
            <span class="truncate font-medium text-ink-muted">
              {@current_scope.scope.tenant.name}
            </span>
            <span class="tabular-nums">#{@current_scope.scope.tenant.id}</span>
            <span
              :if={@current_scope.scope.tenant.is_platform_operator}
              class="hidden text-ink-faint sm:inline"
            >
              · platform operator
            </span>
          </p>
        </div>
      </header>

      <div id="app-workspace" class="relative flex min-h-0 flex-1 overflow-hidden">
        <div
          id="app-sidebar-backdrop"
          class="app-sidebar-backdrop fixed inset-x-0 top-7 bottom-6 z-30 bg-ink/35 opacity-0 lg:hidden"
          aria-hidden="true"
        >
        </div>

        <aside
          id="app-sidebar"
          class="app-sidebar fixed top-7 bottom-6 left-0 z-40 flex w-56 shrink-0 flex-col border-r border-line bg-surface lg:static lg:inset-auto lg:top-auto lg:bottom-auto lg:z-auto lg:w-60"
          tabindex="-1"
          role="navigation"
          aria-label="Main navigation"
        >
          <nav
            id="app-nav"
            aria-label="Main navigation"
            class="flex-1 overflow-y-auto px-1 py-1"
          >
            <.nav_branch
              :for={node <- @nav}
              node={node}
              active_nav={@active_nav}
              depth={0}
            />
            <p
              :if={@nav == []}
              id="app-nav-empty"
              class="app-nav-empty px-2 py-3 text-xs leading-snug text-ink-subtle"
            >
              No navigation is available for this account. An operator needs to
              assign a role.
              <span :if={@shell.dev?} id="app-nav-empty-dev">
                In development, run
                <code class="font-medium text-ink-muted">mix bilimbi.authz.reconcile</code>
                then assign <code class="font-medium text-ink-muted">core_admin</code>
                to this user.
              </span>
            </p>
          </nav>

          <div id="app-user" class="border-t border-line px-1 py-1">
            <div class="flex items-center gap-2 rounded-none px-1 py-0.5 text-sm text-ink-muted transition hover:bg-surface-sunken">
              <span class="grid size-7 shrink-0 place-items-center rounded-full bg-action text-xs font-medium text-action-ink">
                {user_initials(@current_scope.user["name"])}
              </span>
              <div class="app-user-expanded min-w-0 flex-1">
                <p id="app-user-name" class="truncate text-sm font-medium text-ink">
                  {@current_scope.user["name"]}
                </p>
                <p class="truncate text-xs text-ink-subtle">{@current_scope.user["email"]}</p>
              </div>
              <.link
                href={~p"/session"}
                method="delete"
                id="app-logout"
                class="grid size-6 shrink-0 place-items-center rounded-sm text-ink-subtle transition hover:bg-surface-sunken hover:text-ink"
                aria-label="Log out"
                title="Log out"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              </.link>
            </div>
          </div>
        </aside>

        <div
          id="app-sidebar-drag"
          class="app-sidebar-drag relative z-20 hidden w-2 shrink-0 cursor-col-resize hover:bg-surface-sunken lg:block"
          role="separator"
          aria-orientation="vertical"
          aria-label="Resize sidebar"
        >
        </div>

        <main
          id="app-content"
          class="min-h-0 min-w-0 flex-1 overflow-y-auto px-1 py-2 sm:px-4 sm:py-1"
        >
          {render_slot(@inner_block)}
        </main>
      </div>

      <footer
        id="app-statusbar"
        class="flex h-6 shrink-0 items-center justify-between border-t border-line bg-surface px-4 text-xs text-ink-subtle"
      >
        <div class="flex min-w-0 items-center gap-4 overflow-hidden">
          <span
            :if={@shell.dev?}
            id="app-env"
            class="shrink-0 tabular-nums"
            title={env_title(@shell)}
          >
            dev <span :if={@shell.listen_address} id="app-listen">{@shell.listen_address}</span>
          </span>
        </div>
        <span id="app-version" class="shrink-0 tabular-nums" title={"Bilimbi #{@shell.version}"}>
          v{@shell.version}
        </span>
      </footer>
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
      title={render_slot(@inner_block)}
      class={[
        "app-nav-item relative flex items-center gap-2.5 rounded-none px-2 py-1.5 text-sm transition",
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
      <span class="app-nav-label truncate">{render_slot(@inner_block)}</span>
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
      class="app-nav-section px-2 pt-3 pb-1 text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-ink-faint select-none"
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

  attr(:size, :integer, required: true)

  defp brand_mark(assigns) do
    ~H"""
    <img
      src={~p"/images/logo.svg"}
      alt=""
      class={[
        "shrink-0 object-contain",
        @size == 36 && "size-9",
        @size == 24 && "size-6"
      ]}
      width={@size}
      height={@size}
      decoding="async"
      loading="eager"
      aria-hidden="true"
    />
    """
  end

  # Mix env :dev is the only environment chrome. Test and prod render none
  # of it. There is no separate debug flag.
  defp shell_meta do
    dev? = Application.get_env(:bilimbi_base_ui, :mix_env, :prod) == :dev

    %{
      dev?: dev?,
      listen_address: if(dev?, do: Application.get_env(:bilimbi_base_ui, :listen_address)),
      version: Application.get_env(:bilimbi_base_ui, :app_version, "0.1.0")
    }
  end

  defp env_title(%{listen_address: address}) when is_binary(address), do: "dev · #{address}"
  defp env_title(_shell), do: "dev"

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
