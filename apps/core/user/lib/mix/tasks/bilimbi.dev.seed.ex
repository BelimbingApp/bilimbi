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

  `mix bilimbi.server` runs the same work at every development start-up as
  `mix bilimbi.dev.seed --at-startup`, after migrating. That form reports
  what changed and says nothing on a database that is already seeded; a
  refusal to promote existing identities is one information line there, so
  the server still starts, while the plain command fails on it. Nothing
  else differs: reference data is seeded and nobody is promoted either way.

  The seed needs no Geonames reference data: on a database that has none,
  the development company has no jurisdiction and the module sample seeds
  that need a country leave their sample out. Import the reference data with
  `mix bilimbi.geonames.import` when the sample should be complete.

  This task refuses to run outside the `dev` Mix environment.
  """

  use Mix.Task

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  @tenant_name "Bilimbi local development"
  # No jurisdiction: a company's jurisdiction must be a known Geonames
  # country, and a fresh database has none until `mix bilimbi.geonames.import`
  # runs. The seed must succeed before that, so the development company
  # starts without one.
  @company_attributes %{
    name: "Bilimbi Development",
    code: "bilimbi_dev",
    legal_name: "Bilimbi Development",
    metadata: %{"purpose" => "local_development"}
  }
  @user_attributes %{
    name: "AI Agent",
    email: "ai@agent.my",
    password: "bilimbi-dev"
  }

  # Bootstrap answers these when the database already holds identities that
  # carry no receipt: an adopted Belimbing database or a development database
  # seeded before receipts existed. Promoting them is refused by design.
  @identity_refusals [:existing_users, :existing_platform_operator]

  @typedoc """
  What one seed run did: the production seed results as
  `Bilimbi.Base.Database.run_production_seeds/2` reports them, the
  administrator bootstrap status, and how many module sample seeds ran.
  """
  @type report :: %{
          seeds: [map()],
          administrator: :created | :already_completed,
          module_seeds: non_neg_integer()
        }

  @impl Mix.Task
  def run(arguments) do
    at_startup? = parse!(arguments)
    ensure_development!()
    Mix.Task.run("app.start")

    case seed() do
      {:ok, report} ->
        report(report, at_startup?)

      {:refused, %{reason: reason, seeds: seeds}} when at_startup? ->
        report_seeds(seeds)
        Mix.shell().info(refusal_message(reason))

      {:refused, %{reason: reason, seeds: seeds}} ->
        report_seeds(seeds)
        Mix.raise("development seed refused: #{refusal_message(reason)}")

      {:error, message} ->
        Mix.raise(message)
    end
  end

  @doc """
  Seeds installed production reference data, bootstraps the development
  administrator, and runs the module sample seeds, in that order.

  Returns `{:refused, %{reason: reason, seeds: seeds}}` when the database
  already holds identities without a bootstrap receipt: the reference data
  is seeded by then (those are the `seeds` results), no account is promoted,
  and the sample seeds do not run. Any other failure is `{:error, message}`.
  Callers decide what a refusal means; the task fails on it and the
  development server reports it.
  """
  @spec seed() ::
          {:ok, report()} | {:refused, %{reason: atom(), seeds: [map()]}} | {:error, String.t()}
  def seed do
    with {:ok, seeds} <- production_seeds(),
         {:ok, status} <- bootstrap(seeds),
         {:ok, company} <- Company.platform_operator_company(),
         {:ok, scope} <- Tenancy.scope(company.tenant_id) do
      {:ok,
       %{seeds: seeds, administrator: status, module_seeds: run_module_seeds!(scope, company.id)}}
    else
      {:refused, refusal} -> {:refused, refusal}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, "development seed failed: #{inspect(reason)}"}
    end
  end

  defp production_seeds do
    case Database.run_production_seeds(Database.installed_production_seeds!()) do
      {:ok, seeds} ->
        {:ok, seeds}

      {:error, _failure} ->
        {:error, "development reference seed failed; inspect the production-seed ledger"}
    end
  end

  defp bootstrap(seeds) do
    case User.bootstrap_platform_admin(bootstrap_attributes()) do
      {:ok, status} ->
        {:ok, status}

      {:error, reason} when reason in @identity_refusals ->
        {:refused, %{reason: reason, seeds: seeds}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bootstrap_attributes do
    %{
      tenant_name: @tenant_name,
      company_name: @company_attributes.name,
      company_code: @company_attributes.code,
      legal_name: @company_attributes.legal_name,
      metadata: @company_attributes.metadata,
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

  # The plain command always says what it did. At start-up only news is
  # printed: reference seeds applied in this run, and the login when it was
  # just created. An already-seeded database adds no line to the server log.
  defp report(report, false) do
    Mix.shell().info(ready_message(report))
  end

  defp report(%{seeds: seeds, administrator: administrator} = report, true) do
    report_seeds(seeds)
    if administrator == :created, do: Mix.shell().info(ready_message(report))
  end

  defp report_seeds(seeds) do
    for %{status: status, id: id} <- seeds, status != :skipped do
      Mix.shell().info("#{status}: #{id}")
    end
  end

  defp ready_message(%{administrator: status, module_seeds: seeded}) do
    "Development seed ready: administrator #{status}, " <>
      user_message(status) <> module_seed_message(seeded)
  end

  defp refusal_message(reason) do
    "this database already has #{refusal_subject(reason)} without a bootstrap receipt, " <>
      "so no account was promoted (reference data is seeded). Sign in with an existing " <>
      "administrator, or use a fresh development database for #{@user_attributes.email}."
  end

  defp refusal_subject(:existing_users), do: "user accounts"
  defp refusal_subject(:existing_platform_operator), do: "a platform operator"

  defp module_seed_message(0), do: ", no module sample data"
  defp module_seed_message(count), do: ", #{count} module seed(s)"

  defp user_message(:created) do
    "user #{@user_attributes.email} (created). Password: #{@user_attributes.password}."
  end

  defp user_message(:already_completed) do
    "user #{@user_attributes.email} (existing; password preserved)."
  end

  defp parse!([]), do: false
  defp parse!(["--at-startup"]), do: true

  defp parse!(_arguments) do
    Mix.raise("bilimbi.dev.seed accepts no argument other than --at-startup")
  end

  defp ensure_development! do
    if Mix.env() != :dev do
      Mix.raise("bilimbi.dev.seed can only run in the dev Mix environment")
    end
  end
end
