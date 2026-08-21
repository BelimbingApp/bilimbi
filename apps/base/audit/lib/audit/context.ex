defmodule Bilimbi.Base.Audit.Context do
  @moduledoc """
  Per-process actor/request context for captured mutations (ADR 0013).

  The port of Belimbing's `RequestContext`: the web edge resolves it once
  per HTTP request or LiveView process — the same lifecycle as the locale —
  and capture reads it when shaping rows. Absent context degrades to the
  source's guest default (`actor_type "guest"`, `actor_id 0`) rather than
  failing the write; background work that wants attribution sets its own.

  This is presentation-of-actor state, not authorization: nothing reads it
  to decide anything, only to record who did what.
  """

  @key __MODULE__

  defstruct actor_type: "guest",
            actor_id: 0,
            actor_role: nil,
            company_id: nil,
            tenant_id: nil,
            ip_address: nil,
            url: nil,
            user_agent: nil,
            trace_id: nil

  @type t :: %__MODULE__{
          actor_type: String.t(),
          actor_id: non_neg_integer(),
          actor_role: String.t() | nil,
          company_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil,
          ip_address: String.t() | nil,
          url: String.t() | nil,
          user_agent: String.t() | nil,
          trace_id: String.t() | nil
        }

  @spec put(t() | nil) :: :ok
  def put(nil) do
    Process.delete(@key)
    :ok
  end

  def put(%__MODULE__{} = context) do
    Process.put(@key, context)
    :ok
  end

  @doc "The process context, or the guest default when none was set."
  @spec get() :: t()
  def get, do: Process.get(@key) || %__MODULE__{}
end
