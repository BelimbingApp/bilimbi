defmodule Bilimbi.Base.Media.AttachmentSubjectAuthorizer do
  @moduledoc """
  Subject owner's live access policy for private attachments.

  `authorize/4` must resolve the subject through its owning public API using the
  received tenant scope, refuse missing/deleted subjects, and ask its operation
  capability. Actions are `:upload`, `:submit` (also retention), and `:download`.
  Attachment metadata is supplied for submit/download; upload receives `[]`.
  Return `:ok` or `{:error, reason}`. Do not trust subject IDs or uploader IDs as
  proof of permission. Media rechecks this callback on every operation.
  Register the adapter through a `:media` contribution, including exact legacy
  PHP class aliases when adopting a polymorphic subject. No persisted string is
  evaluated as an Elixir module name.
  """
  alias Bilimbi.Base.Tenancy.Scope

  @callback authorize(Scope.t(), :upload | :submit | :download, String.t(), [map()]) ::
              :ok | {:error, term()}
end
