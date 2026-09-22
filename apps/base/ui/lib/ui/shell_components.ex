defmodule Bilimbi.Base.UI.ShellComponents do
  @moduledoc "Shared account disclosure, safety context and immediate display controls."
  use Phoenix.Component
  import Bilimbi.Base.UI.Components
  alias Bilimbi.Base.UI.IconRegistry

  use Phoenix.VerifiedRoutes,
    router: Bilimbi.Base.UI.RouteContract,
    endpoint: Bilimbi.Base.UI.ScriptPath,
    statics: ~w(assets fonts images favicon.ico favicon.svg robots.txt)

  attr :id, :string, required: true
  attr :current_scope, :map, required: true

  def account_menu(assigns) do
    ~H"""
    <div id={@id} class="relative border-t border-line p-1" data-account-menu>
      <button
        id={@id <> "-toggle"}
        type="button"
        data-account-toggle
        aria-expanded="false"
        aria-controls={@id <> "-panel"}
        aria-label="Account and scope"
        title="Account and scope"
        class="flex w-full items-center gap-2 rounded-md p-0.5 text-left text-link hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
      >
        <span class="grid size-7 shrink-0 place-items-center rounded-full bg-action text-xs font-medium text-action-ink">
          {initials(@current_scope.user["name"])}
        </span>
        <span class="app-user-expanded min-w-0 truncate text-xs">{@current_scope.user["name"]}</span>
      </button>
      <section
        id={@id <> "-panel"}
        data-account-panel
        hidden
        aria-label="Account and scope"
        class="absolute bottom-full left-1 z-50 mb-1 w-72 max-w-[calc(100vw-1rem)] rounded-xl border border-line bg-surface p-3 text-xs text-ink shadow-lg"
      >
        <p id={@id <> "-name"} class="break-words text-sm font-semibold">
          {@current_scope.user["name"]}
        </p>
        <p class="break-all text-muted">{@current_scope.user["email"]}</p>
        <dl class="my-3 space-y-2 border-y border-line py-2">
          <div>
            <dt class="text-muted">Company</dt><dd class="break-words">
              {@current_scope.user["company_name"] || "Company unavailable"}
            </dd>
          </div>
          <div>
            <dt class="text-muted">Tenant</dt><dd class="break-words">
              {@current_scope.scope.tenant.name}
              <span class="tabular-nums text-muted">#{@current_scope.scope.tenant.id}</span>
            </dd>
          </div>
          <%!-- The tenant's standing, not a personal entitlement: an account in
               the operator company may still be refused operator-only surfaces.
               It keeps the caution tokens the impersonation strip uses. --%>
          <div
            :if={@current_scope.scope.tenant.is_platform_operator}
            id={@id <> "-platform-operator"}
            class="rounded-md border border-warning-line bg-warning-surface px-2 py-1 text-warning-ink"
          >
            <dt class="sr-only">Access</dt>
            <dd class="inline-flex items-center gap-1.5">
              <.icon name={IconRegistry.shell(:warning)} class="size-4" /> Platform-operator
            </dd>
          </div>
        </dl>
        <div class="space-y-1">
          <.link
            id={@id <> "-password"}
            navigate={~p"/settings/password"}
            class="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
          >
            <.icon name={IconRegistry.shell(:password)} class="size-4" /> Change password
          </.link>
          <.link
            id={@id <> "-logout"}
            href={~p"/session"}
            method="delete"
            class="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
          >
            <.icon name={IconRegistry.shell(:logout)} class="size-4" /> Sign out
          </.link>
        </div>
      </section>
    </div>
    """
  end

  @doc """
  The transient access strip above the workspace.

  It renders only while the session is impersonating, because that state has
  an exit the operator must be able to reach from anywhere. The standing
  platform-operator marker belongs in `account_menu/1`.
  """
  attr :id, :string, required: true
  attr :current_scope, :map, required: true

  def scope_warning(assigns) do
    ~H"""
    <div
      :if={@current_scope[:impersonator]}
      id={@id}
      role="note"
      aria-label="Access warning"
      class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-1 border-b border-warning-line bg-warning-surface px-3 py-1 text-xs text-warning-ink"
    >
      <.link
        href={~p"/admin/impersonate/leave"}
        method="post"
        id="app-impersonation-stop"
        class="inline-flex items-center gap-1.5 underline underline-offset-2"
      >
        <.icon name="bilimbi-impersonate" class="size-4" />
        Viewing as {@current_scope.user["name"]} · Stop
      </.link>
    </div>
    """
  end

  @doc """
  The top bar's timezone and theme controls.

  The bar is `h-7` with no vertical padding, so every control in it is the
  `size-6` inline size the sidebar toggle uses; a `size-7` control would fill
  the bar and paint its pressed and hover surfaces onto the bar's border.
  """
  attr :id, :string, required: true
  attr :preferences, :map, required: true
  attr :impersonating, :boolean, required: true

  def display_controls(assigns) do
    ~H"""
    <div id={@id} class="flex min-w-0 items-center gap-1" data-display-controls>
      <p
        :if={@impersonating}
        id={@id <> "-locked"}
        class="inline-flex min-w-0 items-center gap-1.5 text-xs text-muted"
      >
        <.icon name={IconRegistry.shell(:clock)} class="size-4 shrink-0" />
        <span class="truncate">
          {mode_label(@preferences.mode)} time · display preferences are not editable while viewing as another user
        </span>
      </p>
      <div :if={!@impersonating} class="relative flex" data-timezone-menu>
        <button
          type="button"
          id={@id <> "-timezone"}
          data-timezone-toggle
          aria-expanded="false"
          aria-controls={@id <> "-timezone-panel"}
          aria-label="Select timezone display mode"
          title={"Time display: " <> mode_label(@preferences.mode)}
          class="inline-flex h-6 items-center gap-1 rounded-sm px-1 text-xs text-link hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
        >
          <.icon name={IconRegistry.shell(:clock)} class="size-4" />
          <span class="max-w-28 truncate">{mode_label(@preferences.mode)}</span>
          <.icon name={IconRegistry.shell(:chevron)} class="size-3" />
        </button>
        <div
          id={@id <> "-timezone-panel"}
          data-timezone-panel
          hidden
          class="absolute right-0 top-full z-50 mt-1 w-64 max-w-[calc(100vw-1rem)] rounded-xl border border-line bg-surface p-1 shadow-lg"
          aria-label="Time display"
        >
          <button
            :for={mode <- @preferences.modes}
            type="button"
            id={@id <> "-" <> to_string(mode)}
            data-preference-kind="timezone"
            data-preference-value={to_string(mode)}
            aria-pressed={to_string(@preferences.mode == mode)}
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs text-link hover:bg-surface-muted aria-pressed:bg-brand-surface aria-pressed:text-brand-strong focus-visible:ring-2 focus-visible:ring-brand-strong disabled:opacity-50"
          >
            <.icon name={IconRegistry.shell(:clock)} class="size-4" />
            <span>{mode_choice_label(mode)}<span :if={mode == :company} class="block text-muted">{@preferences.timezone}</span></span>
          </button>
        </div>
      </div>
      <div :if={!@impersonating} class="flex items-center" role="group" aria-label="Theme">
        <.icon_button
          :for={{value, icon} <- [{"light", :light}, {"dark", :dark}, {"system", :system}]}
          id={@id <> "-" <> value}
          context={:inline}
          data-preference-kind="theme"
          data-preference-value={value}
          label={String.capitalize(value)}
          icon={IconRegistry.shell(icon)}
          aria-pressed={to_string(@preferences.theme == value)}
          class="aria-pressed:bg-brand-surface aria-pressed:text-brand-strong"
        />
      </div>
    </div>
    """
  end

  @doc "The compact label the top bar shows for the active time display."
  def mode_label(:company), do: "Company"
  def mode_label(:local), do: "Local"
  def mode_label(:utc), do: "UTC"

  @doc """
  The full label a chooser shows for a time display.

  Every surface that offers the choice — the top-bar clock and the appearance
  screen — renders these, so the two cannot describe the same mode differently.
  """
  def mode_choice_label(:company), do: "Company time"
  def mode_choice_label(:local), do: "This device's local time"
  def mode_choice_label(:utc), do: "Stored UTC"

  defp initials(name),
    do:
      name
      |> to_string()
      |> String.split()
      |> Enum.take(2)
      |> Enum.map_join(&String.first/1)
      |> String.upcase()
end
