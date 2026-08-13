defmodule Bilimbi.Base.ModuleRegistry.ContributionConsumer do
  @moduledoc """
  Validation boundary implemented by each contribution consumer.

  ModuleRegistry owns provider discovery and provenance. Consumers own the
  payload below their key and return the validated immutable snapshot that
  their public API will read.
  """

  @type entry :: %{descriptor: map(), payload: term()}

  @callback validate_contributions!([entry()]) :: term()
end
