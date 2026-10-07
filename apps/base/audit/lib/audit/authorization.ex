defmodule Bilimbi.Base.Audit.Authorization do
  @moduledoc """
  What the sealed scope may do with an audit row and what it may read of one.

  Base Audit defines the questions and gains no dependency on whoever answers
  them. Base Authz already depends on Audit, so the reverse edge would be a
  cycle. The workspace wires the answer in `:bilimbi_base_audit,
  :authorization`. A missing or unloaded answer refuses the change.

  The second question is which fields of a recorded value the reader may not
  see. The module that owns a record declares its field policy
  (`Bilimbi.Base.Authz.put_field_restriction/4`), and a mutation of such a record is
  read through that same policy, so the audit views never show a value the
  record's own page withholds. Without an answer nothing is declared and
  every recorded value reads as recorded: the audit screens are themselves
  reachable only through Authz, which is what supplies the answer.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @callback can?(Scope.t(), String.t()) :: boolean()

  @callback withheld_fields(Scope.t(), [String.t()]) :: %{String.t() => [String.t()]}

  @doc """
  Whether `scope` holds `capability` right now.

  The configured module is asked only when it is loaded. Otherwise the answer
  is no, so a package test or a miswired release cannot change a row.
  """
  @spec can?(Scope.t(), String.t()) :: boolean()
  def can?(%Scope{} = scope, capability) when is_binary(capability) do
    case Application.get_env(:bilimbi_base_audit, :authorization) do
      module when is_atom(module) and not is_nil(module) ->
        Code.ensure_loaded?(module) and module.can?(scope, capability)

      _missing ->
        false
    end
  end

  @doc """
  The fields of each auditable type the scope may not see, by the names a
  recorded value keys them by. A type with nothing withheld is absent.
  """
  @spec withheld_fields(Scope.t(), [String.t()]) :: %{String.t() => [String.t()]}
  def withheld_fields(%Scope{} = scope, types) when is_list(types) do
    case Application.get_env(:bilimbi_base_audit, :authorization) do
      module when is_atom(module) and not is_nil(module) ->
        if Code.ensure_loaded?(module), do: module.withheld_fields(scope, types), else: %{}

      _missing ->
        %{}
    end
  end
end
