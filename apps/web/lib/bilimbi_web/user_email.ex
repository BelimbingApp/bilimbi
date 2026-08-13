defmodule BilimbiWeb.UserEmail do
  @moduledoc false

  import Swoosh.Email

  use Phoenix.VerifiedRoutes,
    endpoint: BilimbiWeb.Endpoint,
    router: BilimbiWeb.Router,
    statics: BilimbiWeb.static_paths()

  alias Bilimbi.Core.User.Summary

  def password_reset(%Summary{} = user, token) when is_binary(token) do
    reset_url =
      BilimbiWeb.Endpoint.url() <>
        ~p"/reset-password/#{token}?#{[email: user.email]}"

    new()
    |> to({user.name, user.email})
    |> from({"Bilimbi", "no-reply@bilimbi.local"})
    |> subject("Reset your Bilimbi password")
    |> text_body("""
    Reset your Bilimbi password by opening this link:

    #{reset_url}

    If you did not request this, you can ignore this email.
    """)
  end
end
