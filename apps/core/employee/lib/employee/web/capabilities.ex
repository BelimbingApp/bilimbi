defmodule Bilimbi.Core.Employee.Web.Capabilities do
  @moduledoc false

  @spec allowed?(map() | nil, String.t()) :: boolean()
  def allowed?(%{capabilities: capabilities}, capability)
      when is_list(capabilities) and is_binary(capability) do
    capability in capabilities
  end

  def allowed?(_current_scope, _capability), do: false
end
