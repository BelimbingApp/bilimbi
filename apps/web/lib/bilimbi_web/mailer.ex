defmodule BilimbiWeb.Mailer do
  use Swoosh.Mailer, otp_app: :web

  @spec sender() :: {String.t(), String.t()}
  def sender, do: Application.fetch_env!(:web, :mailer_sender)
end
