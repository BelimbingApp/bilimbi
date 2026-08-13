defmodule BilimbiWeb.MailerConfigTest do
  use ExUnit.Case, async: true

  alias BilimbiWeb.MailerConfig

  @environment %{
    "MAIL_HOST" => "smtp.example.com",
    "MAIL_PORT" => "587",
    "MAIL_USERNAME" => "bilimbi",
    "MAIL_PASSWORD" => "secret",
    "MAIL_TLS_MODE" => "starttls",
    "MAIL_FROM_NAME" => "Bilimbi",
    "MAIL_FROM_ADDRESS" => "no-reply@example.com"
  }

  test "builds a certificate-verifying STARTTLS configuration" do
    config = MailerConfig.smtp_config!(@environment)

    assert config[:adapter] == Swoosh.Adapters.SMTP
    assert config[:relay] == "smtp.example.com"
    assert config[:port] == 587
    assert config[:username] == "bilimbi"
    assert config[:password] == "secret"
    assert config[:auth] == :always
    assert config[:ssl] == false
    assert config[:tls] == :always
    assert config[:tls_options][:verify] == :verify_peer
    assert config[:tls_options][:server_name_indication] == ~c"smtp.example.com"
  end

  test "builds a certificate-verifying implicit TLS configuration" do
    config =
      @environment
      |> Map.put("MAIL_PORT", "465")
      |> Map.put("MAIL_TLS_MODE", "implicit_tls")
      |> MailerConfig.smtp_config!()

    assert config[:ssl] == true
    assert config[:tls] == :never
    assert config[:sockopts][:verify] == :verify_peer
    assert config[:sockopts][:server_name_indication] == ~c"smtp.example.com"
  end

  test "rejects an insecure or unknown TLS mode" do
    assert_raise ArgumentError, "MAIL_TLS_MODE must be either starttls or implicit_tls", fn ->
      @environment
      |> Map.put("MAIL_TLS_MODE", "never")
      |> MailerConfig.smtp_config!()
    end
  end

  test "rejects malformed required values" do
    assert_raise ArgumentError, "MAIL_HOST must be set", fn ->
      @environment
      |> Map.delete("MAIL_HOST")
      |> MailerConfig.smtp_config!()
    end

    assert_raise ArgumentError, "MAIL_PORT must be an integer between 1 and 65535", fn ->
      @environment
      |> Map.put("MAIL_PORT", "smtp")
      |> MailerConfig.smtp_config!()
    end

    assert_raise ArgumentError, "MAIL_FROM_ADDRESS must be a valid email address", fn ->
      @environment
      |> Map.put("MAIL_FROM_ADDRESS", "not-an-address")
      |> MailerConfig.sender!()
    end
  end
end
