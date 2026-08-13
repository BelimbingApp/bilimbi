defmodule Bilimbi.Core.User.PasswordResetToken do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:email, :string, autogenerate: false}

  schema "password_reset_tokens" do
    field :token, :string
    field :created_at, :naive_datetime
  end

  @type t :: %__MODULE__{}

  @spec changeset(String.t(), String.t(), NaiveDateTime.t()) :: Ecto.Changeset.t()
  def changeset(email, token, created_at) do
    %__MODULE__{}
    |> change(email: email, token: token, created_at: created_at)
    |> validate_required([:email, :token])
    |> validate_length(:email, max: 255)
    |> validate_length(:token, max: 255)
  end
end
