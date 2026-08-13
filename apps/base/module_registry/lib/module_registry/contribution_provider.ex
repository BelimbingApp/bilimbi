defmodule Bilimbi.Base.ModuleRegistry.ContributionProvider do
  @moduledoc """
  Provider contract for descriptor-owned installed-module contributions.

  Providers run once when the deployment contribution snapshot is built. They
  return consumer-owned plain terms and must not perform I/O or depend on
  request, tenant, or process-local state.
  """

  @type consumer :: :settings | :authz | :menu

  @callback contributions() :: %{optional(consumer()) => term()}
end
