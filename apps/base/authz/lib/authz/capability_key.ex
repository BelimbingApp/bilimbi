defmodule Bilimbi.Base.Authz.CapabilityKey do
  @moduledoc "Validation and parsing for durable authorization capability keys."

  @segment "[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
  @pattern Regex.compile!("^#{@segment}(?:\\.#{@segment}){2,}$")

  @type parts :: %{domain: String.t(), resource: String.t(), action: String.t()}

  @spec valid?(term()) :: boolean()
  def valid?(key) when is_binary(key), do: Regex.match?(@pattern, key)
  def valid?(_key), do: false

  @spec parse!(String.t()) :: parts()
  def parse!(key) when is_binary(key) do
    unless valid?(key), do: raise(ArgumentError, "invalid capability key: #{inspect(key)}")

    [domain | rest] = String.split(key, ".")
    {resource_parts, [action]} = Enum.split(rest, -1)

    %{domain: domain, resource: Enum.join(resource_parts, "."), action: action}
  end
end
