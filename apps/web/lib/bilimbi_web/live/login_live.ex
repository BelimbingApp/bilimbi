defmodule BilimbiWeb.LoginLive do
  @moduledoc """
  The Bilimbi sign-in screen — the application homepage.

  Behavior mirrors Belimbing's `Core/User/Livewire/Auth/Login`:

    * email + password, both required, email format checked live;
    * a neutral credential failure on the email field
      ("These credentials do not match our records.");
    * five attempts per email+IP per minute, then a lockout that names the
      remaining seconds;
    * a session-expired notice when an expired session is bounced here;
    * on success, a painted "Signed in. Opening your workspace…" state while
      the session form submits and the browser navigates.

  What differs is Bilimbi's own: the workspace strip under the card names
  the platform this is signing into, and the geometry follows `DESIGN.md`'s
  compact ledger rules rather than Belimbing's arid pill styling.
  """

  use BilimbiWeb, :live_view

  alias Bilimbi.Core.Company
  alias BilimbiWeb.RateLimit
  alias BilimbiWeb.UserAuth

  @login_types %{email: :string, password: :string}

  @impl true
  def mount(_params, _session, socket) do
    throttle_key = throttle_key(socket)

    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:throttle_key, throttle_key)
     |> assign(:phase, :editing)
     |> assign(:trigger_action, false)
     |> assign(:login_token, nil)
     |> assign(:form_error, nil)
     |> assign_workspace()
     |> assign_form(login_changeset(%{}))}
  end

  @impl true
  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply, assign_form(socket, login_changeset(params))}
  end

  def handle_event("login", %{"login" => params}, socket) do
    changeset = login_changeset(params)

    if changeset.valid? do
      attempt_login(socket, changeset)
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp attempt_login(socket, changeset) do
    case RateLimit.attempt_allowed?(socket.assigns.throttle_key) do
      :allow -> verify_credentials(socket, changeset)
      {:deny, seconds} -> {:noreply, reject(socket, changeset, throttle_message(seconds))}
    end
  end

  defp verify_credentials(socket, changeset) do
    %{email: email, password: password} = Ecto.Changeset.apply_action!(changeset, :login)

    case UserAuth.authenticate(email, password) do
      {:ok, user} ->
        complete_login(socket, user)

      {:error, :invalid_credentials} ->
        :ok = RateLimit.record_attempt(socket.assigns.throttle_key)
        {:noreply, reject(socket, changeset, "These credentials do not match our records.")}
    end
  end

  defp complete_login(socket, user) do
    case UserAuth.session_user(user) do
      {:ok, session_user} ->
        :ok = RateLimit.reset(socket.assigns.throttle_key)

        {:noreply,
         socket
         |> assign(:phase, :opening)
         |> assign(:login_token, UserAuth.sign_login_token(session_user))
         |> assign(:trigger_action, true)}

      {:error, :tenant_unavailable} ->
        {:noreply,
         assign(socket, :form_error, "This account is not attached to an active workspace.")}
    end
  end

  defp reject(socket, changeset, message) do
    changeset =
      changeset
      |> Ecto.Changeset.add_error(:email, message)
      |> Map.put(:action, :validate)

    socket
    |> assign(:form_error, nil)
    |> assign_form(changeset)
  end

  defp throttle_message(seconds) do
    minutes = max(1, ceil(seconds / 60))

    "Too many sign-in attempts. Try again in #{minutes} #{ngettext("minute", "minutes", minutes)}."
  end

  defp login_changeset(attrs) do
    {%{}, @login_types}
    |> Ecto.Changeset.cast(attrs, [:email, :password])
    |> Ecto.Changeset.validate_required([:email, :password])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> Map.put(:action, :validate)
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "login"))
  end

  defp throttle_key(socket) do
    peer =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> :inet.ntoa(address) |> to_string()
        _ -> "unknown"
      end

    {:login, peer}
  end

  # The workspace strip: platform-level, non-tenant-owned identity, readable
  # before authentication by design (Company.platform_operator_company/0).
  defp assign_workspace(socket) do
    case Company.platform_operator_company() do
      {:ok, company} ->
        socket
        |> assign(:workspace_state, :ready)
        |> assign(:workspace_company, company)

      {:error, state} ->
        socket
        |> assign(:workspace_state, state)
        |> assign(:workspace_company, nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="flex flex-col gap-5">
        <div :if={@flash["session_expired"]} id="login-session-expired">
          <.alert kind={:warning}>Your session expired. Sign in again to continue.</.alert>
        </div>

        <div :if={@phase == :opening} id="login-opening" role="status">
          <.alert kind={:info}>Signed in. Opening your workspace…</.alert>
        </div>

        <div :if={@form_error} id="login-form-error">
          <.alert kind={:error}>{@form_error}</.alert>
        </div>

        <.form
          for={@form}
          id="login-form"
          action={~p"/session"}
          method="post"
          phx-change="validate"
          phx-submit="login"
          phx-trigger-action={@trigger_action}
          class="flex flex-col gap-4"
        >
          <input type="hidden" name="login[_token]" value={@login_token} />

          <.input
            field={@form[:email]}
            id="login-email"
            type="email"
            label="Email address"
            placeholder="email@example.com"
            autocomplete="email"
            required
            autofocus
          />

          <div class="relative">
            <.input
              field={@form[:password]}
              id="login-password"
              type="password"
              label="Password"
              placeholder="Password"
              autocomplete="current-password"
              required
            />
            <span
              id="login-forgot-password"
              class="absolute inset-x-0 -top-0.5 text-right text-xs text-ink-subtle"
              title="Password reset arrives with the Core User authentication slice"
            >
              Forgot your password?
            </span>
          </div>

          <.button
            type="submit"
            variant="primary"
            id="login-submit"
            class="w-full"
            phx-disable-with="Signing in…"
            disabled={@phase == :opening}
          >
            <%= if @phase == :opening do %>
              Opening workspace…
            <% else %>
              Log in
            <% end %>
          </.button>
        </.form>

        <div
          id="login-workspace"
          data-state={@workspace_state}
          class="flex items-center justify-center gap-2 border-t border-line-subtle pt-4 text-xs text-ink-subtle"
        >
          <%= if @workspace_state == :ready do %>
            <span class="size-1.5 rounded-full bg-success"></span>
            <span class="truncate">
              <span class="font-medium text-ink-muted">
                {Bilimbi.Core.Company.Summary.display_name(@workspace_company)}
              </span>
              <span class="text-ink-faint">
                · tenant <span class="tabular-nums">{@workspace_company.tenant_id}</span>
              </span>
            </span>
          <% else %>
            <span class="size-1.5 rounded-full bg-warning"></span>
            <span>Platform workspace not provisioned</span>
          <% end %>
        </div>
      </div>
    </Layouts.auth>
    """
  end
end
