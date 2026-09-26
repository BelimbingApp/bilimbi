defmodule BilimbiWeb.ScopeActorBoundaryTest do
  @moduledoc """
  Only Bilimbi's authentication edge attaches a user to a scope.

  `Bilimbi.Base.Tenancy.Authentication.sign_in/4` takes user and company IDs
  from its caller, so any module that calls it could make a scope say anyone
  performed its work. Elixir has no function visible to one caller, so this
  test is the fence: it reads the remote calls every compiled Bilimbi module
  makes — from the BEAM import table, so aliases, multi-aliases, and macro
  expansion cannot hide one — and fails for a caller outside the allowlist.

  The seal (`ActorSeal`) is fenced the same way: anything that could compute
  one could forge an actor.

  Web runs this because Web loads every installed module, mounted Domains and
  Extensions included. Adding a caller is an architecture change: name it
  here with the reason, and expect review to ask why the edge is not enough.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.Tenancy.ActorSeal
  alias Bilimbi.Base.Tenancy.Authentication

  @fences %{
    {Authentication, :sign_in} => [
      # Proves the durable session, user, company, and tenant, then signs in.
      BilimbiWeb.UserAuth
    ],
    {Authentication, :resume} => [
      # Rebuilds the scope of a job enqueued with Queue.enqueue_for/3.
      Bilimbi.Base.Queue.Worker
    ],
    {ActorSeal, :system} => [Bilimbi.Base.Tenancy.Scope],
    {ActorSeal, :user} => [Authentication],
    {ActorSeal, :verify!} => [Bilimbi.Base.Tenancy.Scope],
    {ActorSeal, :sign_delegation} => [Authentication],
    {ActorSeal, :verify_delegation} => [Authentication]
  }

  test "only the authentication edge can attach an actor to a scope" do
    calls = fenced_calls()

    offenders =
      for {fence, callers} <- calls,
          caller <- callers,
          caller not in Map.fetch!(@fences, fence),
          do: "#{inspect(caller)} calls #{format(fence)}"

    assert offenders == [],
           """
           These modules reach the scope-actor seam, which only Bilimbi's
           authentication edge may call (see Bilimbi.Base.Tenancy.Authentication).
           Take the actor from Scope.actor/1 instead:

           #{Enum.map_join(Enum.sort(offenders), "\n", &("  " <> &1))}
           """
  end

  test "every allowlisted caller still calls its fence, so the list cannot rot" do
    calls = fenced_calls()

    stale =
      for {fence, allowed} <- @fences,
          caller <- allowed,
          caller not in Map.get(calls, fence, []),
          do: "#{inspect(caller)} no longer calls #{format(fence)}"

    assert stale == [], "Remove stale allowlist entries:\n" <> Enum.join(stale, "\n")
  end

  defp fenced_calls do
    modules = bilimbi_modules()
    assert length(modules) > 100, "expected the Web host to load every Bilimbi module"

    for module <- modules,
        {callee, function, _arity} <- imports(module),
        fence = {callee, function},
        Map.has_key?(@fences, fence),
        reduce: %{} do
      acc -> Map.update(acc, fence, [module], &Enum.uniq([module | &1]))
    end
  end

  defp bilimbi_modules do
    for {app, _description, _version} <- Application.loaded_applications(),
        module <- Application.spec(app, :modules) || [],
        bilimbi_module?(module),
        do: module
  end

  defp bilimbi_module?(module) do
    name = Atom.to_string(module)
    String.starts_with?(name, "Elixir.Bilimbi.") or String.starts_with?(name, "Elixir.BilimbiWeb")
  end

  defp imports(module) do
    case :code.which(module) do
      path when is_list(path) ->
        {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(path, [:imports])
        imports

      _not_on_disk ->
        []
    end
  end

  defp format({module, function}), do: "#{inspect(module)}.#{function}"
end
