defmodule Bilimbi.Base.Tenancy.NotProvisionedError do
  @moduledoc """
  Raised when an operation requires a platform operator before one is provisioned.
  """

  defexception message: "the platform-operator tenant has not been provisioned"
end
