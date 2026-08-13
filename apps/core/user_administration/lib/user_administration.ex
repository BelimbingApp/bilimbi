defmodule Bilimbi.Core.UserAdministration do
  @moduledoc """
  Bounded, tenant-scoped read model for the Users administration index.

  The facade returns schema-free presentation data. It does not authorize an
  actor and does not expose a queryable; the web adapter owns capability
  enforcement and calls Core User's public APIs for commands.
  """

  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.UserAdministration.ConsumedRelations
  alias Bilimbi.Core.UserAdministration.Options
  alias Bilimbi.Core.UserAdministration.Page
  alias Bilimbi.Core.UserAdministration.Query

  @doc """
  Lists one bounded page of tenant-visible Users.

  Options are strict and already normalized: `:search`, `:role_ids`,
  `:sort_by`, `:sort_dir`, `:page`, and `:page_size`. Unknown or malformed
  options raise `ArgumentError`. Page is capped at 1,000,000, keeping the
  largest supported page-size offset below 100 million rows and well inside
  PostgreSQL's signed-bigint `OFFSET` range.
  """
  @spec list_users(Scope.t(), keyword()) :: Page.t()
  def list_users(%Scope{} = scope, options \\ []) do
    ConsumedRelations.verify!()
    Query.list(scope, Options.new!(options))
  end
end
