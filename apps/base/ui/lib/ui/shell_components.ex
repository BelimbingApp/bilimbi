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

  attr :id, :string, required: true
  attr :current_scope, :map, required: true

  def scope_warning(assigns) do
    ~H"""
    <div
      :if={@current_scope.scope.tenant.is_platform_operator || @current_scope[:impersonator]}
      id={@id}
      role="note"
      aria-label="Access warning"
      class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-1 border-b border-warning-line bg-warning-surface px-3 py-1 text-xs text-warning-ink"
    >
      <span
        :if={@current_scope.scope.tenant.is_platform_operator}
        class="inline-flex items-center gap-1.5"
      >
        <.icon name={IconRegistry.shell(:warning)} class="size-4" /> Platform-operator access
      </span>
      <.link
        :if={@current_scope[:impersonator]}
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

  attr :id, :string, required: true
  attr :preferences, :map, required: true
  attr :impersonating, :boolean, required: true

  def display_controls(assigns) do
    ~H"""
    <div id={@id} class="flex shrink-0 items-center gap-1" data-display-controls>
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
      <div :if={!@impersonating} class="relative" data-timezone-menu>
        <button
          type="button"
          id={@id <> "-timezone"}
          data-timezone-toggle
          aria-expanded="false"
          aria-controls={@id <> "-timezone-panel"}
          aria-label="Select timezone display mode"
          title={"Time display: " <> mode_label(@preferences.mode)}
          class="inline-flex h-7 items-center gap-1 rounded-md px-1 text-xs text-link hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-strong"
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
            :for={
              {value, label} <- [
                {"company", "Company time"},
                {"local", "This device's local time"},
                {"utc", "Stored UTC"}
              ]
            }
            type="button"
            id={@id <> "-" <> value}
            data-preference-kind="timezone"
            data-preference-value={value}
            aria-pressed={to_string(to_string(@preferences.mode) == value)}
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs text-link hover:bg-surface-muted aria-pressed:bg-brand-surface aria-pressed:text-brand-strong focus-visible:ring-2 focus-visible:ring-brand-strong disabled:opacity-50"
          >
            <.icon name={IconRegistry.shell(:clock)} class="size-4" />
            <span>{label}<span :if={value == "company"} class="block text-muted">{@preferences.timezone}</span></span>
          </button>
        </div>
      </div>
      <div :if={!@impersonating} class="flex items-center" role="group" aria-label="Theme">
        <.icon_button
          :for={{value, icon} <- [{"light", :light}, {"dark", :dark}, {"system", :system}]}
          id={@id <> "-" <> value}
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

  defp mode_label(:company), do: "Company"
  defp mode_label(:local), do: "Local"
  defp mode_label(:utc), do: "UTC"

  defp initials(name),
    do:
      name
      |> to_string()
      |> String.split()
      |> Enum.take(2)
      |> Enum.map_join(&String.first/1)
      |> String.upcase()
end
