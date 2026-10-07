defmodule Mix.Tasks.Bilimbi.Dev.Seed do
  @shortdoc "Seeds the local development platform identity and login"

  @moduledoc """
  Seeds the identity and login required to use Bilimbi in local development.

      mix bilimbi.dev.seed

  The seed provisions an explicitly marked platform-operator tenant and its
  primary company through the public Company API, then creates the development
  login through the public User API:

      Email: ai@agent.my
      Password: bilimbi-dev

  It seeds installed production reference data, then uses User's one-time
  administrator bootstrap. Repeats preserve passwords and revoked roles.
  Existing identities without a bootstrap receipt are refused rather than
  promoted. The owning modules then contribute their development sample data.

  This task refuses to run outside the `dev` Mix environment.
  """

  use Mix.Task

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  @tenant_name "Bilimbi local development"
  @company_attributes %{
    name: "Bilimbi Development",
    code: "bilimbi_dev"
  }
  @user_attributes %{
    name: "AI Agent",
    email: "ai@agent.my",
    password: "bilimbi-dev"
  }

  @impl Mix.Task
  def run(arguments) do
    reject_arguments!(arguments)
    ensure_development!()
    Mix.Task.run("app.start")

    with {:ok, _seeds} <- Database.run_production_seeds(Database.installed_production_seeds!()),
         {:ok, status} <- User.bootstrap_platform_admin(bootstrap_attributes()),
         {:ok, company} <- Company.platform_operator_company(),
         {:ok, scope} <- Tenancy.scope(company.tenant_id) do
      seeded = run_module_seeds!(scope, company.id)

      Mix.shell().info(
        "Development seed ready: administrator #{status}, " <>
          user_message(status) <>
          module_seed_message(seeded)
      )
    else
      {:error, reason} when is_atom(reason) ->
        Mix.raise("development seed failed: #{inspect(reason)}")

      {:error, _seed_failure} ->
        Mix.raise("development reference seed failed; inspect the production-seed ledger")
    end
  end

  defp bootstrap_attributes do
    %{
      tenant_name: @tenant_name,
      company_name: @company_attributes.name,
      company_code: @company_attributes.code,
      admin_name: @user_attributes.name,
      admin_email: @user_attributes.email,
      password: @user_attributes.password
    }
  end

  # Each installed module may own dev sample data at `priv/dev_seed.exs` (declared
  # via the `dev_seed` descriptor key). base/module_registry discovers them in
  # dependency order — so a module's script may reference an earlier one's data
  # through a right-direction public API — and each is evaluated with `scope` and
  # `company_id` bound. The task's dev-env guard covers every script.
  defp run_module_seeds!(scope, company_id) do
    paths = ModuleRegistry.dev_seed_paths!()
    Enum.each(paths, &eval_module_seed!(&1, scope, company_id))
    length(paths)
  end

  defp eval_module_seed!(path, scope, company_id) do
    Code.eval_string(File.read!(path), [scope: scope, company_id: company_id], file: path)
  rescue
    error ->
      Mix.raise("dev seed #{Path.relative_to_cwd(path)} failed: #{Exception.message(error)}")
  end

  defp module_seed_message(0), do: ", no module sample data"
  defp module_seed_message(count), do: ", #{count} module seed(s)"

  defp user_message(:created) do
    "user #{@user_attributes.email} (created). Password: #{@user_attributes.password}."
  end

  defp user_message(:already_completed) do
    "user #{@user_attributes.email} (existing; password preserved)."
  end

  defp reject_arguments!([]), do: :ok

  defp reject_arguments!(_arguments) do
    Mix.raise("bilimbi.dev.seed accepts no arguments")
  end

  defp ensure_development! do
    if Mix.env() != :dev do
      Mix.raise("bilimbi.dev.seed can only run in the dev Mix environment")
    end
  end
end
