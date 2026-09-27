defmodule Mix.Tasks.Bilimbi.Authz.SystemPrincipal do
  @shortdoc "Lists, grants, and revokes capabilities of named system principals"

  @moduledoc """
  The operator's path for administering named system principals (ADR 0017).

      mix bilimbi.authz.system_principal declared
      mix bilimbi.authz.system_principal grants --tenant 3 [--principal coating.line_import]
      mix bilimbi.authz.system_principal grant --tenant 3 --company 7 \\
        --principal coating.line_import --capability factory.material.import
      mix bilimbi.authz.system_principal revoke --tenant 3 --company 7 \\
        --principal coating.line_import --capability factory.material.import

  `declared` lists the principals installed modules declare and the
  capabilities each may be granted. A grant names one declared capability for
  one company of the tenant; nothing is granted by default, and nothing but
  a grant allows.

  Whoever can run this task has a shell on the server and needs no sign-in,
  like the database console. Grants and revocations made here are therefore
  recorded as `console`: an `authz.system_principal.granted` or `.revoked`
  audit action, committed with the change, and the captured row write.
  Signed-in administrators use `Bilimbi.Base.Authz.grant_system_capability/4`
  and `revoke_system_capability/4`, which record the user.
  """

  use Mix.Task

  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.SystemPrincipalService
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy

  @switches [tenant: :integer, company: :integer, principal: :string, capability: :string]
  @console %{actor_type: "console", actor_id: 0}

  @impl Mix.Task
  def run([command | arguments]) when command in ~w(declared grants grant revoke) do
    {options, positional, invalid} = OptionParser.parse(arguments, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise("invalid arguments; run mix help bilimbi.authz.system_principal")
    end

    Mix.Task.run("app.start")
    command(command, options)
  end

  def run(_arguments),
    do:
      Mix.raise(
        "expected declared, grants, grant, or revoke; run mix help bilimbi.authz.system_principal"
      )

  defp command("declared", []) do
    case Authz.list_system_principals() do
      [] ->
        Mix.shell().info("No installed module declares a system principal.")

      principals ->
        for principal <- principals do
          Mix.shell().info("#{principal.name} (#{principal.module_id}): #{principal.description}")

          for capability <- principal.capabilities do
            Mix.shell().info("  may be granted #{capability}")
          end
        end
    end
  end

  defp command("grants", options) do
    scope = scope!(options)
    grants = SystemPrincipalService.list(scope, Keyword.take(options, [:principal]), registry())

    if grants == [] do
      Mix.shell().info("No system principal holds a capability in tenant #{options[:tenant]}.")
    end

    for grant <- grants do
      Mix.shell().info("#{grant.principal} company #{grant.company_id}: #{grant.capability}")
    end
  end

  defp command("grant", options) do
    {scope, company_id, principal, capability} = change_options!(options)

    case as_console(fn ->
           SystemPrincipalService.grant(
             scope,
             company_id,
             principal,
             capability,
             @console,
             registry()
           )
         end) do
      {:ok, :granted} ->
        Mix.shell().info("Granted #{capability} to #{principal} in company #{company_id}.")

      {:ok, :existing} ->
        Mix.shell().info("#{principal} already holds #{capability} in company #{company_id}.")

      {:error, reason} ->
        Mix.raise("grant refused: #{inspect(reason)}")
    end
  end

  defp command("revoke", options) do
    {scope, company_id, principal, capability} = change_options!(options)

    case as_console(fn ->
           SystemPrincipalService.revoke(
             scope,
             company_id,
             principal,
             capability,
             @console,
             registry()
           )
         end) do
      {:ok, :revoked} ->
        Mix.shell().info("Revoked #{capability} from #{principal} in company #{company_id}.")

      {:ok, :not_found} ->
        Mix.shell().info("#{principal} holds no #{capability} in company #{company_id}.")

      {:error, reason} ->
        Mix.raise("revoke refused: #{inspect(reason)}")
    end
  end

  defp command(command, _options),
    do: Mix.raise("#{command} takes no options; run mix help bilimbi.authz.system_principal")

  defp change_options!(options) do
    scope = scope!(options)

    {scope, required!(options, :company), required!(options, :principal),
     required!(options, :capability)}
  end

  defp scope!(options) do
    tenant_id = required!(options, :tenant)

    case Tenancy.scope(tenant_id) do
      {:ok, scope} -> scope
      {:error, reason} -> Mix.raise("tenant #{tenant_id} is unavailable: #{inspect(reason)}")
    end
  end

  defp required!(options, key) do
    case Keyword.get(options, key) do
      nil -> Mix.raise("--#{key} is required")
      value -> value
    end
  end

  # The captured grant-row write names the console too, not the guest default.
  defp as_console(fun) do
    previous = AuditContext.get()
    AuditContext.put(%AuditContext{actor_type: "console", actor_id: 0})

    try do
      fun.()
    after
      AuditContext.put(previous)
    end
  end

  defp registry, do: ContributionRegistry.consumer!(:authz)
end
