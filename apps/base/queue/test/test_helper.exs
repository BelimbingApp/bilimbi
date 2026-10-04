Code.ensure_loaded!(Bilimbi.Base.Database.DataCase)
Code.ensure_loaded!(Bilimbi.Base.Tenancy.TestFixtures)

ExUnit.start()

alias Bilimbi.Base.Queue
alias Bilimbi.Base.Repo

unless Oban.whereis(Queue.oban_config()[:name]) do
  raise "the supervised Base Queue runtime did not start"
end

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
