defmodule Bilimbi.Base.Tenancy.ForgedActorError do
  @moduledoc """
  Raised when a scope's actor does not carry the seal the edge gave it.

  It means code built or changed the actor instead of receiving it from
  Bilimbi's authentication edge: a struct literal, a struct update, or an
  actor moved onto another tenant's scope. It is never a user error, and
  nothing should rescue it.
  """

  defexception message: "the scope's actor was not issued by Bilimbi's authentication edge"
end
