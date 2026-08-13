defmodule BilimbiWeb.ForgotPasswordLive do
  use BilimbiWeb, :live_view

  alias Bilimbi.Core.User
  alias BilimbiWeb.{Mailer, UserEmail}

  @confirmation "A reset link will be sent if the account exists."
  @types %{email: :string}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Forgot password")
     |> assign(:confirmation, nil)
     |> assign_form(changeset(%{}))}
  end

  @impl true
  def handle_event("validate", %{"forgot" => params}, socket) do
    {:noreply, assign_form(socket, changeset(params))}
  end

  def handle_event("request-reset", %{"forgot" => params}, socket) do
    changeset = changeset(params)

    if changeset.valid? do
      %{email: email} = Ecto.Changeset.apply_action!(changeset, :request_reset)

      User.request_password_reset(email, fn user, token ->
        case user |> UserEmail.password_reset(token) |> Mailer.deliver() do
          {:ok, _metadata} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)

      {:noreply, assign(socket, :confirmation, @confirmation)}
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp changeset(attrs) do
    {%{}, @types}
    |> Ecto.Changeset.cast(attrs, [:email])
    |> Ecto.Changeset.validate_required([:email])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> Map.put(:action, :validate)
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "forgot"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="flex flex-col gap-5">
        <div>
          <h1 class="text-lg font-semibold tracking-tight text-ink-strong">Forgot your password?</h1>
          <p class="mt-1 text-sm text-ink-muted">Enter your email address to request a reset link.</p>
        </div>

        <div :if={@confirmation} id="forgot-confirmation">
          <.alert kind={:success}>{@confirmation}</.alert>
        </div>

        <.form
          for={@form}
          id="forgot-form"
          phx-change="validate"
          phx-submit="request-reset"
          class="flex flex-col gap-4"
        >
          <.input
            field={@form[:email]}
            id="forgot-email"
            type="email"
            label="Email address"
            placeholder="email@example.com"
            autocomplete="email"
            required
            autofocus
          />

          <.button
            type="submit"
            variant="primary"
            id="forgot-submit"
            class="w-full"
            phx-disable-with="Sending…"
          >
            Send reset link
          </.button>
        </.form>

        <.link
          navigate={~p"/"}
          id="forgot-back"
          class="text-center text-sm text-action hover:underline"
        >
          Back to sign in
        </.link>
      </div>
    </Layouts.auth>
    """
  end
end
