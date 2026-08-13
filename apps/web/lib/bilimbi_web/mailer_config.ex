defmodule BilimbiWeb.MailerConfig do
  @moduledoc false

  @required_variables ~w(
    MAIL_HOST
    MAIL_PORT
    MAIL_USERNAME
    MAIL_PASSWORD
    MAIL_TLS_MODE
    MAIL_FROM_NAME
    MAIL_FROM_ADDRESS
  )

  @type environment :: %{required(String.t()) => String.t()}

  @spec production_config!() :: keyword()
  def production_config! do
    required_environment!()
    |> smtp_config!()
  end

  @spec sender!() :: {String.t(), String.t()}
  def sender! do
    environment = required_environment!()
    {required!(environment, "MAIL_FROM_NAME"), sender_address!(environment)}
  end

  @spec smtp_config!(environment()) :: keyword()
  def smtp_config!(environment) when is_map(environment) do
    relay = required!(environment, "MAIL_HOST")

    [
      adapter: Swoosh.Adapters.SMTP,
      relay: relay,
      port: port!(required!(environment, "MAIL_PORT")),
      username: required!(environment, "MAIL_USERNAME"),
      password: required!(environment, "MAIL_PASSWORD"),
      auth: :always
    ] ++ transport_config(required!(environment, "MAIL_TLS_MODE"), relay)
  end

  @spec sender!(environment()) :: {String.t(), String.t()}
  def sender!(environment) when is_map(environment) do
    {required!(environment, "MAIL_FROM_NAME"), sender_address!(environment)}
  end

  defp required_environment! do
    Map.new(@required_variables, fn variable -> {variable, System.fetch_env!(variable)} end)
  end

  defp transport_config("starttls", relay) do
    [ssl: false, tls: :always, tls_options: tls_options(relay)]
  end

  defp transport_config("implicit_tls", relay) do
    [ssl: true, tls: :never, sockopts: tls_options(relay)]
  end

  defp transport_config(_, _relay) do
    raise ArgumentError, "MAIL_TLS_MODE must be either starttls or implicit_tls"
  end

  defp tls_options(relay) do
    [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(relay),
      depth: 99,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp required!(environment, variable) do
    case Map.get(environment, variable) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          raise ArgumentError, "#{variable} must be set"
        end

        value

      _ ->
        raise ArgumentError, "#{variable} must be set"
    end
  end

  defp port!(value) do
    case Integer.parse(value) do
      {port, ""} when port in 1..65_535 -> port
      _ -> raise ArgumentError, "MAIL_PORT must be an integer between 1 and 65535"
    end
  end

  defp sender_address!(environment) do
    address = required!(environment, "MAIL_FROM_ADDRESS")

    if valid_email_address?(address) do
      address
    else
      raise ArgumentError, "MAIL_FROM_ADDRESS must be a valid email address"
    end
  end

  defp valid_email_address?(address), do: String.match?(address, ~r/^[^\s@]+@[^\s@]+$/)
end
