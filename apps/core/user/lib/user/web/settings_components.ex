defmodule Bilimbi.Core.User.Web.SettingsComponents do
  @moduledoc """
  Shared UI layout and components for user self-service settings pages.
  """

  use Bilimbi.Base.UI, :html

  attr(:current_page, :atom, required: true, values: [:profile, :password, :appearance])
  attr(:heading, :string, required: true)
  attr(:subheading, :string, default: nil)
  slot(:inner_block, required: true)

  def settings_layout(assigns) do
    ~H"""
    <div class="w-full">
      <div class="relative mb-2 w-full">
        <%!-- The shared <.header> (text-lg text-action) keeps this shell on
             the same heading system as every other screen (#653). --%>
        <.header>
          Settings
          <:subtitle>Manage your profile and account settings</:subtitle>
        </.header>
        <hr class="border-line" />
      </div>

      <div class="flex items-start max-md:flex-col">
        <div class="me-10 w-full pb-4 md:w-[220px] shrink-0">
          <nav class="flex flex-col space-y-1">
            <.link
              navigate={~p"/settings/profile"}
              class={[
                "rounded-lg px-4 py-2 text-sm transition-colors",
                @current_page == :profile && "bg-surface-muted font-medium text-action",
                @current_page != :profile && "text-muted hover:bg-surface-muted hover:text-ink"
              ]}
            >
              Profile
            </.link>

            <.link
              navigate={~p"/settings/password"}
              class={[
                "rounded-lg px-4 py-2 text-sm transition-colors",
                @current_page == :password && "bg-surface-muted font-medium text-action",
                @current_page != :password && "text-muted hover:bg-surface-muted hover:text-ink"
              ]}
            >
              Password
            </.link>

            <.link
              navigate={~p"/settings/appearance"}
              class={[
                "rounded-lg px-4 py-2 text-sm transition-colors",
                @current_page == :appearance && "bg-surface-muted font-medium text-action",
                @current_page != :appearance && "text-muted hover:bg-surface-muted hover:text-ink"
              ]}
            >
              Appearance
            </.link>
          </nav>
        </div>

        <hr class="md:hidden border-line my-4 w-full" />

        <div class="flex-1 self-stretch max-md:pt-2">
          <h2 class="text-lg font-semibold text-ink">{@heading}</h2>
          <p :if={@subheading} class="text-sm text-muted">{@subheading}</p>

          <div class="mt-5 w-full max-w-lg">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
