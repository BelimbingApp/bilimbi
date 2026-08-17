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
  #
  # `:any` rather than `:string` so `nil` is expressible: some pages genuinely
  # own no menu item -- Belimbing's profile screen is one -- and the guard
  # exists to forbid *forgetting*, not to forbid saying "none". Typed
  # `:string`, the honest answer was a compile warning, which would have
  # pushed the next author into inventing a menu id to satisfy the compiler.
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
          class="app-sidebar fixed top-7 bottom-6 left-0 z-40 flex w-56 shrink-0 flex-col border-r border-line bg-surface-sidebar lg:static lg:inset-auto lg:top-auto lg:bottom-auto lg:z-auto lg:w-60"
          tabindex="-1"
          role="navigation"
          aria-label="Main navigation"
        >
          <div id="app-pinned" class="app-pinned bg-surface-muted px-0.5 py-0.5" hidden>
            <p class="app-pinned-heading px-1 pt-0.5 pb-px text-[0.65rem] font-medium uppercase tracking-[0.14em] text-ink-faint select-none">
              Pinned
            </p>
            <div id="app-pinned-items"></div>
            <div class="app-pinned-divider mx-1 my-0.5 h-px bg-line/60" aria-hidden="true"></div>
          </div>

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
              assign a role — in development, run
              <code class="font-medium text-ink-muted">mix bilimbi.authz.reconcile</code>
              then assign <code class="font-medium text-ink-muted">core_admin</code>
              to this user.
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
  attr(:label, :string, required: true)

  defp nav_item(assigns) do
    ~H"""
    <div class="app-nav-item-row group flex min-w-0 items-center">
      <.link
        navigate={@navigate}
        id={@id}
        data-nav-item={@id}
        data-nav-label={@label}
        aria-current={@active && "page"}
        title={@label}
        class={[
          "app-nav-item relative flex min-w-0 flex-1 items-center gap-1 rounded-none px-1 py-px text-sm font-normal transition",
          @active && "bg-surface font-medium text-ink-strong",
          !@active && "text-ink-muted hover:bg-surface-sunken hover:text-ink"
        ]}
      >
        <span
          :if={@active}
          class="app-nav-active-spine absolute inset-y-1 left-0 w-0.5 rounded-full bg-brand-strong"
          aria-hidden="true"
        ></span>
        <span class="app-nav-indent w-3 shrink-0 text-center" aria-hidden="true">&#8199;</span>
        <.icon
          name={@icon}
          class={["app-nav-icon size-[1.125rem] shrink-0", @active && "text-brand-strong"]}
        />
        <span class="app-nav-label min-w-0 truncate">{@label}</span>
      </.link>
      <.nav_pin item_id={@id} label={@label} />
    </div>
    """
  end

  attr(:node, :map, required: true)
  attr(:active_nav, :string, default: nil)
  attr(:depth, :integer, default: 0)

  defp nav_branch(assigns) do
    item = assigns.node.item
    dom_id = nav_dom_id(item.id)
    branch? = assigns.node.children != []
    expanded? = nav_branch_open?(assigns.node, assigns.active_nav)

    assigns =
      assigns
      |> assign(:branch?, branch?)
      |> assign(:dom_id, dom_id)
      |> assign(:expanded?, expanded?)
      |> assign(:active?, item.id == assigns.active_nav)

    ~H"""
    <.nav_item
      :if={not @branch? and @node.item.route}
      navigate={@node.item.route}
      icon={nav_icon(@node.item.icon)}
      active={@active?}
      id={"nav-" <> @dom_id}
      label={@node.item.label}
    />

    <section
      :if={@branch?}
      id={"nav-branch-" <> @dom_id}
      data-nav-branch={@node.item.id}
      data-nav-default-expanded={to_string(@expanded?)}
      data-nav-expanded={to_string(@expanded?)}
      class="app-nav-branch"
    >
      <div class="app-nav-parent flex min-w-0 items-center px-1 py-px text-sm font-normal text-ink-muted transition hover:bg-surface-sunken hover:text-ink">
        <button
          :if={is_nil(@node.item.route)}
          id={"nav-toggle-" <> @dom_id}
          type="button"
          data-nav-toggle
          aria-controls={"nav-children-" <> @dom_id}
          aria-expanded={to_string(@expanded?)}
          aria-label={"Toggle " <> @node.item.label}
          title={@node.item.label}
          class="app-nav-container flex min-w-0 flex-1 items-center gap-1 text-left"
        >
          <.icon name="hero-chevron-right" class="app-nav-caret size-3 shrink-0 transition-transform" />
          <.icon name={nav_icon(@node.item.icon)} class="app-nav-icon size-[1.125rem] shrink-0" />
          <span class="app-nav-label min-w-0 truncate">{@node.item.label}</span>
        </button>

        <button
          :if={@node.item.route}
          id={"nav-toggle-" <> @dom_id}
          type="button"
          data-nav-toggle
          aria-controls={"nav-children-" <> @dom_id}
          aria-expanded={to_string(@expanded?)}
          aria-label={"Toggle " <> @node.item.label}
          title={@node.item.label}
          class="app-nav-toggle grid size-4 shrink-0 place-items-center rounded-sm text-ink-muted transition hover:bg-surface hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
        >
          <.icon name="hero-chevron-right" class="app-nav-caret size-3 transition-transform" />
          <span class="sr-only">Toggle {@node.item.label}</span>
        </button>

        <.link
          :if={@node.item.route}
          navigate={@node.item.route}
          id={"nav-" <> @dom_id}
          data-nav-item={"nav-" <> @dom_id}
          data-nav-label={@node.item.label}
          aria-current={@active? && "page"}
          title={@node.item.label}
          class={[
            "app-nav-parent-link relative flex min-w-0 flex-1 items-center gap-1 rounded-none px-1 py-px transition",
            @active? && "font-medium text-ink-strong",
            !@active? && "text-ink-muted hover:text-ink"
          ]}
        >
          <span
            :if={@active?}
            class="app-nav-active-spine absolute inset-y-0 left-0 w-0.5 rounded-full bg-brand-strong"
            aria-hidden="true"
          ></span>
          <.icon
            name={nav_icon(@node.item.icon)}
            class={["app-nav-icon size-[1.125rem] shrink-0", @active? && "text-brand-strong"]}
          />
          <span class="app-nav-label min-w-0 truncate">{@node.item.label}</span>
        </.link>
        <.nav_pin
          :if={@node.item.route}
          item_id={"nav-" <> @dom_id}
          label={@node.item.label}
        />
      </div>

      <div
        id={"nav-children-" <> @dom_id}
        class="app-nav-children ml-3"
        hidden={!@expanded?}
      >
        <.nav_branch
          :for={child <- @node.children}
          node={child}
          active_nav={@active_nav}
          depth={@depth + 1}
        />
      </div>
    </section>
    """
  end

  defp nav_branch_open?(node, active_nav) do
    node.item.id == active_nav or Enum.any?(node.children, &nav_branch_open?(&1, active_nav))
  end

  defp nav_dom_id(id), do: String.replace(id, ".", "-")

  attr(:item_id, :string, required: true)
  attr(:label, :string, required: true)

  defp nav_pin(assigns) do
    ~H"""
    <button
      type="button"
      id={"nav-pin-" <> String.trim_leading(@item_id, "nav-")}
      data-nav-pin={@item_id}
      title={"Pin " <> @label <> " to sidebar"}
      aria-label={"Pin " <> @label <> " to sidebar"}
      class="app-nav-pin grid size-4 shrink-0 place-items-center rounded-sm text-ink-faint opacity-0 transition hover:bg-surface hover:text-ink group-hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
    >
      <.icon name="bilimbi-pin" class="size-3" />
    </button>
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
