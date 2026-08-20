defmodule Bilimbi.Base.ModuleRegistry.ContributionProvider do
  @moduledoc """
  Provider contract for descriptor-owned installed-module contributions.

  ADR 0004 established three consumers: `:settings`, `:authz`, and `:menu`.
  `:dashboard` is a peer consumer following the same contract; it is added as a
  platform-internal consumer for the widget catalogue. The validator map in
  `ContributionRegistry` registers `Bilimbi.Base.Dashboard.ContributionValidator`
  for it, and the lifecycle is identical to the three original consumers.

  Providers run once when the deployment contribution snapshot is built. They
  return consumer-owned plain terms and must not perform I/O or depend on
  request, tenant, or process-local state.
  """

  @type consumer ::
          :settings | :authz | :menu | :dashboard | :principal_directory | :schedule

  @callback contributions() :: %{optional(consumer()) => term()}
end
