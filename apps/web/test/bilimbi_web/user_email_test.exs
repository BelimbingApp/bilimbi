defmodule BilimbiWeb.UserEmailTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.User.Summary
  alias BilimbiWeb.UserEmail

  test "uses the configured sender for password reset email" do
    user = %Summary{id: 1, name: "Ada Lovelace", email: "ada@example.com"}

    email = UserEmail.password_reset(user, "reset-token")

    assert email.from == {"Bilimbi Test", "no-reply@bilimbi.test"}
  end
end
