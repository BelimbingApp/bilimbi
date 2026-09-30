defmodule Bilimbi.Base.Artifacts.Owner do
  @moduledoc """
  Trusted owning-module adapter for sensitive documents.

  The adapter is selected in server code, never from request parameters. Its
  stable ID identifies the business module. `authorize/4` must validate that
  the company is live and belongs to the scope, then recheck the current actor's
  access to the subject and operation. Only literal `:ok` grants access.
  For `:purge`, the reference is nil: authorize company maintenance before
  Base selects any candidate IDs. Each candidate also needs `:delete` access.
  The subject and kind are opaque business identifiers, not filenames.

  Stored artifacts bind both the stable ID and this adapter's module name.
  An unrelated adapter cannot substitute its authorization for an existing
  document. Adapter renames require an explicit owner-reviewed data migration.
  """
  alias Bilimbi.Base.Tenancy.Scope

  @type document_ref :: %{subject: String.t(), kind: String.t()}
  @callback artifact_owner_id() :: String.t()
  @callback authorize(
              Scope.t(),
              pos_integer(),
              :create | :read | :delete | :purge,
              document_ref() | nil
            ) ::
              :ok | {:error, term()}
end
