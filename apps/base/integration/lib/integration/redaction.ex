defmodule Bilimbi.Base.Integration.Redaction do
  @moduledoc "Mandatory redaction at the persistence boundary, including imported payload inspection."

  @secret ~r/authorization|cookie|password|secret|token|apikey|credential|signature/i
  @max_bytes 32_768

  def redact(%{__struct__: _}), do: "[omitted]"

  def redact(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      normalized = key |> to_string() |> String.replace(~r/[_-]/, "")

      {to_string(key),
       if(Regex.match?(@secret, normalized), do: "[redacted]", else: redact(item))}
    end)
  end

  def redact(value) when is_list(value), do: Enum.map(value, &redact/1)

  def redact(value) when is_binary(value) do
    # Opaque strings can contain bearer tokens, URLs or unstructured secrets.
    # Only JSON scalar values under a non-secret key are retained by structured/1.
    "[omitted]"
  end

  def redact(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  def redact(_value), do: "[omitted]"

  def structured(nil), do: nil
  def structured(%{__struct__: _}), do: %{"kind" => "omitted", "reason" => "unstructured"}

  def structured(value) when is_map(value) or is_list(value) do
    redacted = redact(value)

    if byte_size(Jason.encode!(redacted)) <= @max_bytes,
      do: %{"kind" => "json", "value" => redacted},
      else: %{"kind" => "omitted", "reason" => "size_limit"}
  end

  def structured(_value), do: %{"kind" => "omitted", "reason" => "unstructured"}

  def endpoint(url) when is_binary(url) do
    uri = URI.parse(url)
    %{uri | userinfo: nil, query: nil, fragment: nil} |> URI.to_string()
  end
end
