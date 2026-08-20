defmodule Bilimbi.Base.ModuleRegistry.ContributionProvider do
  @moduledoc """
  Provider contract for descriptor-owned installed-module contributions.

  ADR 0004 established `:settings`, `:authz`, and `:menu`. ADRs 0009, 0011,
  and 0012 add the peer `:dashboard`, `:principal_directory`, and `:schedule`
  consumers. Every consumer follows the same eager, provenance-carrying,
  validator-owned snapshot lifecycle.

  Providers run once when the deployment contribution snapshot is built. They
  return consumer-owned plain terms and must not perform I/O or depend on
  request, tenant, or process-local state.
  """

  @type consumer ::
          :settings | :authz | :menu | :dashboard | :principal_directory | :schedule

  @callback contributions() :: %{optional(consumer()) => term()}
end
