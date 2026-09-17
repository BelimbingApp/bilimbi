defmodule Bilimbi.Base.UI.Layouts do
  @moduledoc """
  Shared Bilimbi web shells and feedback surfaces.

  Two shells:

    * `auth/1` — the centered credential layout (login and, later, password
      reset). Compact card on the warm canvas with the Bilimbi brand bar;
      the page is otherwise quiet so the form reads first.
    * `app/1` — the authenticated workspace shell: a full-width top bar,
      a left menu sidebar, and a persistent status bar. Account context is
      disclosed from the bottom-left circle; safety warnings stay visible.

  Navigation sidebar conventions:

    * Typography: `Instrument Sans` compact font styling with warm semantic
      link text and stronger ink on hover.
    * Carets: Triangle glyphs (`&#x2BC8;` and `&#x2BC6;`) for expandable nodes
      and figure-space indentation for leaf items.
    * Active state: Selected items use `bg-surface text-brand-strong` without
      bolding or right spine lines.
    * Parent ascent: All parent branches containing the active item accent in
      `text-brand-strong`.
    * Pinned items: Rendered in `bg-brand-surface` with `rounded-sm`.
    * Collation: Nav roots and submenus sort alphabetically ascending (`ASC`).

  No authenticated screen is context-free.
  """

  use Phoenix.Component
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Bilimbi.Base.UI.Components
  alias Bilimbi.Base.UI.ShellComponents

  alias Phoenix.LiveView.JS

  # How long a `:success` or `:info` flash stays before it dismisses itself.
  # Long enough to read a sentence twice.
  @auto_dismiss_ms 8_000

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
  slot(:topbar_actions)
  slot(:inner_block, required: true)

  def app(assigns) do
    nav = Bilimbi.Base.UI.Nav.tree(assigns.current_scope)

    assigns =
      assigns
      |> assign(:shell, shell_meta())
      |> assign(:nav, nav)
      |> assign(:preferences, assigns.current_scope.shell_preferences)

    ~H"""
    <%!-- `data-display-mode` is published for `<.datetime>`. It comes from a
         tracked assign, so a saved mode change patches it and every instant
         already on screen follows — including rows a LiveView stream handed
         to the DOM, which the server never re-renders. --%>
    <div
      id="app-shell"
      phx-hook="AppShell"
      data-theme-choice={@preferences.theme}
      data-display-mode={@preferences.mode}
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
          <.icon name={Bilimbi.Base.UI.IconRegistry.shell(:navigation)} class="size-5" />
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

          <div class="flex min-w-0 flex-1 items-center justify-end gap-3">
            {render_slot(@topbar_actions)}

            <ShellComponents.display_controls
              id="app-display"
              preferences={@preferences}
              impersonating={@current_scope[:impersonator] != nil}
            />
          </div>
        </div>
      </header>

      <ShellComponents.scope_warning id="app-scope-warning" current_scope={@current_scope} />
      <%!-- No text colour here: ShellControls marks a failure with `text-danger`,
      and a second colour role on the same element would outrank it. Ordinary
      notices inherit `text-ink` from the document body. --%>
      <div
        id="app-preference-feedback"
        hidden
        role="status"
        aria-live="polite"
        class="shrink-0 border-b border-line bg-surface px-3 py-1 text-xs"
      >
      </div>

      <div id="app-workspace" class="relative flex min-h-0 flex-1 overflow-hidden">
        <div
          id="app-sidebar-backdrop"
          class="app-sidebar-backdrop absolute inset-0 z-30 bg-ink/35 opacity-0 lg:hidden"
          aria-hidden="true"
        >
        </div>

        <aside
          id="app-sidebar"
          class="app-sidebar app-nav-rail absolute inset-y-0 left-0 z-40 flex w-56 shrink-0 flex-col border-r border-line bg-surface-sidebar lg:static lg:inset-auto lg:top-auto lg:bottom-auto lg:z-auto lg:w-60"
          tabindex="-1"
          role="navigation"
          aria-label="Main navigation"
        >
          <div id="app-pinned" class="app-pinned bg-brand-surface px-0.5 py-0.5 rounded-sm" hidden>
            <p class="app-pinned-heading px-1 pt-0.5 pb-px text-[0.625rem] font-medium uppercase tracking-[0.14em] text-muted select-none">
              Pinned
            </p>
            <div id="app-pinned-items"></div>
            <div class="app-pinned-divider mx-1 my-0.5 h-px bg-line/50" aria-hidden="true"></div>
          </div>

          <nav
            id="app-nav"
            aria-label="Main navigation"
            class="flex-1 overflow-y-auto px-0.5 py-0.5"
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
              No destinations are available for this account. Ask an operator to assign a role.
            </p>
          </nav>

          <ShellComponents.account_menu id="app-user" current_scope={@current_scope} />
        </aside>

        <div
          id="app-sidebar-drag"
          class="app-sidebar-drag relative z-20 hidden w-2 shrink-0 cursor-col-resize hover:bg-surface-muted lg:block"
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

          <.link
            :if={operator_company_missing?(@current_scope)}
            navigate={~p"/setup/platform-operator"}
            id="app-operator-company-missing"
            class="inline-flex items-center gap-1 font-medium text-danger hover:underline"
          >
            <.icon name={Bilimbi.Base.UI.IconRegistry.shell(:warning)} class="size-3.5" />
            <span>{gettext("Operator company not set")}</span>
          </.link>
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
  attr(:pinnable, :boolean, default: true)

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
          "app-nav-item relative flex min-w-0 flex-1 items-center rounded-none px-1 py-px text-sm font-normal transition",
          @active && "bg-surface text-brand-strong",
          !@active && "text-link hover:bg-surface-muted hover:text-ink"
        ]}
      >
        <span
          class="app-nav-indent text-[11px] shrink-0 w-3 text-center mr-0.5 select-none"
          aria-hidden="true"
        >&#8199;</span>
        <.icon
          name={@icon}
          class={["app-nav-icon size-[1.125rem] shrink-0", @active && "text-brand-strong"]}
        />
        <span class="app-nav-label min-w-0 truncate">{@label}</span>
      </.link>
      <.nav_pin :if={@pinnable} item_id={@id} label={@label} />
    </div>
    """
  end

  @doc """
  One sidebar navigation node: a leaf row, or a branch with its children.

  Public so the Design Library renders the rail the shell actually ships rather
  than a look-alike. `node` is a `Bilimbi.Base.UI.Nav` tree entry —
  `%{item: %Bilimbi.Base.Menu.Item{}, children: [node]}` — and `active_nav` is
  the menu id of the current page, which marks that row and accents its
  ancestors.

  Rows take their type scale, colours, icon suppression and caret direction
  from the `.app-nav-rail` rules in `app.css`, so a container outside
  `#app-sidebar` must carry that class to render what the shell renders.

  `pinnable` is false outside the sidebar. `AppShell.resolvePinnedItem/1`
  resolves a pinned id only against `#app-sidebar`, so a pin control anywhere
  else stores an entry that the next render prunes — a control that looks
  live and does nothing.
  """
  attr(:node, :map, required: true)
  attr(:active_nav, :string, default: nil)
  attr(:depth, :integer, default: 0)
  attr(:pinnable, :boolean, default: true)

  def nav_branch(assigns) do
    item = assigns.node.item
    dom_id = nav_dom_id(item.id)
    branch? = assigns.node.children != []
    expanded? = nav_branch_open?(assigns.node, assigns.active_nav)
    has_active_child? = nav_has_active_child?(assigns.node, assigns.active_nav)

    assigns =
      assigns
      |> assign(:branch?, branch?)
      |> assign(:dom_id, dom_id)
      |> assign(:expanded?, expanded?)
      |> assign(:active?, item.id == assigns.active_nav)
      |> assign(:has_active_child?, has_active_child?)

    ~H"""
    <.nav_item
      :if={not @branch? and @node.item.route}
      navigate={@node.item.route}
      icon={nav_icon(@node.item.icon)}
      active={@active?}
      id={"nav-" <> @dom_id}
      label={@node.item.label}
      pinnable={@pinnable}
    />

    <section
      :if={@branch?}
      id={"nav-branch-" <> @dom_id}
      data-nav-branch={@node.item.id}
      data-nav-default-expanded={to_string(@expanded?)}
      data-nav-expanded={to_string(@expanded?)}
      class="app-nav-branch"
    >
      <div class={[
        "app-nav-parent group flex min-w-0 items-center px-1 py-px text-sm font-normal transition hover:bg-surface-muted",
        (@active? or @has_active_child?) && "text-brand-strong",
        !(@active? or @has_active_child?) && "text-link hover:text-ink"
      ]}>
        <button
          :if={is_nil(@node.item.route)}
          id={"nav-toggle-" <> @dom_id}
          type="button"
          data-nav-toggle
          aria-controls={"nav-children-" <> @dom_id}
          aria-expanded={to_string(@expanded?)}
          aria-label={"Toggle " <> @node.item.label}
          title={@node.item.label}
          class="app-nav-container flex min-w-0 flex-1 items-center text-left"
        >
          <span
            class="app-nav-caret text-[11px] shrink-0 w-3 text-center mr-0.5 select-none"
            aria-hidden="true"
          >
            <span class="app-nav-caret-closed">&#x2BC8;</span>
            <span class="app-nav-caret-open">&#x2BC6;</span>
          </span>
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
          class="app-nav-toggle grid size-5 shrink-0 place-items-center rounded-sm text-link transition hover:bg-surface hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
        >
          <span
            class="app-nav-caret text-[11px] shrink-0 w-3 text-center select-none"
            aria-hidden="true"
          >
            <span class="app-nav-caret-closed">&#x2BC8;</span>
            <span class="app-nav-caret-open">&#x2BC6;</span>
          </span>
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
            "app-nav-parent-link relative flex min-w-0 flex-1 items-center rounded-none px-1 py-px transition",
            @active? && "bg-surface text-brand-strong font-normal",
            !@active? && "text-link hover:text-ink"
          ]}
        >
          <.icon
            name={nav_icon(@node.item.icon)}
            class={["app-nav-icon size-[1.125rem] shrink-0", @active? && "text-brand-strong"]}
          />
          <span class="app-nav-label min-w-0 truncate">{@node.item.label}</span>
        </.link>
        <.nav_pin
          :if={@pinnable and @node.item.route}
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
          pinnable={@pinnable}
        />
      </div>
    </section>
    """
  end

  defp nav_branch_open?(node, active_nav) do
    node.item.id == active_nav or Enum.any?(node.children, &nav_branch_open?(&1, active_nav))
  end

  defp nav_has_active_child?(node, active_nav) do
    Enum.any?(node.children, fn child ->
      child.item.id == active_nav or nav_has_active_child?(child, active_nav)
    end)
  end

  defp nav_dom_id(id), do: String.replace(id, ".", "-")

  attr(:item_id, :string, required: true)
  attr(:label, :string, required: true)

  defp nav_pin(assigns) do
    ~H"""
    <.icon_button
      icon="bilimbi-pin"
      label={"Pin " <> @label <> " to sidebar"}
      context={:inline}
      id={"nav-pin-" <> String.trim_leading(@item_id, "nav-")}
      data-nav-pin={@item_id}
      class="app-nav-pin opacity-0 group-hover:opacity-100 focus-visible:opacity-100"
    />
    """
  end

  # Menu contributions carry bare Heroicon names so a module never encodes the
  # host's icon-set prefix. A fully qualified name is passed through unchanged.
  defp nav_icon(nil), do: "hero-square-3-stack-3d"
  defp nav_icon("hero-" <> _ = name), do: name
  defp nav_icon(name) when is_binary(name), do: "hero-" <> name

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

  defp operator_company_missing?(%{operator_company_missing: true}), do: true
  defp operator_company_missing?(_current_scope), do: false

  @doc """
  The one production outlet for flash messages.

  Messages stack in one column at the top right, most severe first, so several
  are readable at once. Dismissal splits by severity: only `:success` times
  out, after eight seconds, while `:info`, `:warning` and `:error` stay until
  the person dismisses them, because a message someone must act on must not
  disappear on a timer. `:info` is excluded deliberately: callers currently
  use it for actionable failure notices, so it can only start timing out once
  those call sites move to `:success`. The reconnect notices are errors and
  keep that rule.

  The group is a permanent polite live region, so a message inserted into it
  is announced; every message is an alert, whatever its severity.

  The shell's preference status line under the top bar is deliberately not
  part of this outlet: see the Design Library's Feedback section.
  """
  attr(:flash, :map, required: true)
  attr(:id, :string, default: "flash-group")

  def flash_group(assigns) do
    assigns = assign(assigns, :auto_dismiss_ms, @auto_dismiss_ms)

    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="fixed right-4 top-4 z-50 flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-2"
    >
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash
        kind={:success}
        flash={@flash}
        phx-hook="FlashAutoDismiss"
        data-auto-dismiss-ms={@auto_dismiss_ms}
      />
      <.flash kind={:info} flash={@flash} />

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
