defmodule Bilimbi.Base.ModuleRegistry.ContributionProvider do
  @moduledoc """
  Provider contract for descriptor-owned installed-module contributions.

  ADR 0004 established `:settings`, `:authz`, and `:menu`. ADRs 0009, 0011,
  0012, 0016, 0017, 0018, and 0019 add the peer `:dashboard`,
  `:principal_directory`, `:schedule`, `:actor_verifier`,
  `:system_principals`, `:workflow`, and `:grid` consumers. Every consumer
  follows the same eager, provenance-carrying, validator-owned snapshot
  lifecycle.

  Providers run once when the deployment contribution snapshot is built. They
  return consumer-owned plain terms and must not perform I/O or depend on
  request, tenant, or process-local state.
  """

  @type consumer ::
          :settings
          | :authz
          | :menu
          | :dashboard
          | :principal_directory
          | :schedule
          | :actor_verifier
          | :system_principals
          | :workflow
          | :grid

  @callback contributions() :: %{optional(consumer()) => term()}
end
