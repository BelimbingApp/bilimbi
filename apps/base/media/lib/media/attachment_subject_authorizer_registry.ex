defmodule Bilimbi.Base.Media.AttachmentSubjectAuthorizerRegistry do
  @moduledoc "Exact, fail-closed lookup of descriptor-owned attachment subject policies."
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  def fetch(type) when is_binary(type) do
    case Map.fetch(ContributionRegistry.consumer!(:media), type) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :unregistered_subject}
    end
  end

  def authorize(scope, action, type, id, attachments) do
    with {:ok, entry} <- fetch(type) do
      case entry.adapter.authorize(scope, action, id, attachments) do
        :ok -> :ok
        {:error, _} = error -> error
        _ -> {:error, :forbidden}
      end
    end
  end
end
