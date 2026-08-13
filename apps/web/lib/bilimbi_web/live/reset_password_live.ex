defmodule BilimbiWeb.ResetPasswordLive do
  use BilimbiWeb, :live_view

  alias Bilimbi.Core.User

  @types %{email: :string, password: :string, password_confirmation: :string}

  @impl true
  def mount(params, _session, socket) do
    attrs = %{"email" => Map.get(params, "email", "")}

    {:ok,
     socket
     |> assign(:page_title, "Reset password")
     |> assign(:token, params["token"])
     |> assign_form(changeset(attrs))}
  end

  @impl true
  def handle_event("validate", %{"reset" => params}, socket) do
    {:noreply, assign_form(socket, changeset(params))}
  end

  def handle_event("reset-password", %{"reset" => params}, socket) do
    changeset = changeset(params)

    if changeset.valid? do
      %{email: email, password: password} =
        Ecto.Changeset.apply_action!(changeset, :reset_password)

      case User.reset_password(email, socket.assigns.token, password) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Your password has been reset.")
           |> push_navigate(to: ~p"/")}

        {:error, :invalid_or_expired_token} ->
          {:noreply,
           assign_form(
             socket,
             Ecto.Changeset.add_error(
               changeset,
               :email,
               "The password reset link is invalid or has expired."
             )
           )}

        {:error, %Ecto.Changeset{} = password_changeset} ->
          changeset =
            Enum.reduce(password_changeset.errors, changeset, fn
              {:password, {message, metadata}}, acc ->
                Ecto.Changeset.add_error(acc, :password, message, metadata)

              _, acc ->
                acc
            end)

          {:noreply, assign_form(socket, changeset)}
      end
    else
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp changeset(attrs) do
    {%{}, @types}
    |> Ecto.Changeset.cast(attrs, [:email, :password, :password_confirmation])
    |> Ecto.Changeset.validate_required([:email, :password, :password_confirmation])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> Ecto.Changeset.validate_length(:password, min: 8)
    |> Ecto.Changeset.validate_confirmation(:password, required: true)
    |> Map.put(:action, :validate)
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "reset"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="flex flex-col gap-5">
        <div>
          <h1 class="text-lg font-semibold tracking-tight text-ink-strong">Reset your password</h1>
          <p class="mt-1 text-sm text-ink-muted">Choose a new password for your account.</p>
        </div>

        <.form
          for={@form}
          id="reset-form"
          phx-change="validate"
          phx-submit="reset-password"
          class="flex flex-col gap-4"
        >
          <.input
            field={@form[:email]}
            id="reset-email"
            type="email"
            label="Email address"
            autocomplete="email"
            required
            autofocus
          />

          <.input
            field={@form[:password]}
            id="reset-password"
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />

          <.input
            field={@form[:password_confirmation]}
            id="reset-password-confirmation"
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
            required
          />

          <.button
            type="submit"
            variant="primary"
            id="reset-submit"
            class="w-full"
            phx-disable-with="Resetting…"
          >
            Reset password
          </.button>
        </.form>

        <.link
          navigate={~p"/"}
          id="reset-back"
          class="text-center text-sm text-action hover:underline"
        >
          Back to sign in
        </.link>
      </div>
    </Layouts.auth>
    """
  end
end
