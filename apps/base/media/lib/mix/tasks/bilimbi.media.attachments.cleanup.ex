defmodule Mix.Tasks.Bilimbi.Media.Attachments.Cleanup do
  @moduledoc """
  Removes abandoned, unretained attachment drafts for one explicit tenant.

      mix bilimbi.media.attachments.cleanup --tenant ID [--hours 24]

  Submitted evidence and retained drafts are never removed.
  """
  use Mix.Task
  @shortdoc "Deletes abandoned private attachment drafts for one tenant"

  @impl true
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [tenant: :integer, hours: :integer])
    tenant = opts[:tenant]
    hours = Keyword.get(opts, :hours, 24)

    unless rest == [] and invalid == [] and is_integer(tenant) and tenant > 0 and
             is_integer(hours) and hours > 0,
           do:
             Mix.raise(
               "usage: mix bilimbi.media.attachments.cleanup --tenant ID [--hours POSITIVE_INTEGER]"
             )

    Mix.Task.run("app.start")

    with {:ok, scope} <- Bilimbi.Base.Tenancy.scope(tenant),
         {:ok, count} <-
           Bilimbi.Base.Media.cleanup_drafts_before(
             scope,
             NaiveDateTime.add(NaiveDateTime.utc_now(), -hours * 3600, :second)
           ) do
      Mix.shell().info("Removed #{count} abandoned attachment draft(s).")
    else
      {:error, reason} -> Mix.raise("Attachment cleanup failed: #{inspect(reason)}")
    end
  end
end
