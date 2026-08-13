defmodule Bilimbi.Base.Authz.ContributionValidator do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Authz.CapabilityKey
  alias Bilimbi.Base.Authz.CompanyDirectory

  @payload_keys [:capabilities, :company_directory, :domains, :roles, :verbs]
  @role_keys [:capabilities, :description, :grant_all, :name]
  @segment ~r/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/
  @role_code ~r/^[a-z][a-z0-9_]*$/

  @impl true
  def validate_contributions!(entries) when is_list(entries) do
    entries
    |> Enum.reduce(empty_snapshot(), &merge_entry!/2)
    |> finalize!()
  end

  defp empty_snapshot do
    %{
      domains: %{},
      domain_owners: %{},
      verbs: %{},
      capabilities: %{},
      roles: %{},
      company_directory: nil
    }
  end

  defp merge_entry!(%{descriptor: descriptor, payload: payload}, snapshot)
       when is_map(payload) do
    unknown_keys = Map.keys(payload) -- @payload_keys

    if unknown_keys != [] do
      invalid!(descriptor.id, "unknown keys: #{inspect(Enum.sort(unknown_keys))}")
    end

    snapshot
    |> merge_domains!(descriptor.id, Map.get(payload, :domains, %{}))
    |> merge_verbs!(descriptor.id, Map.get(payload, :verbs, []))
    |> merge_capabilities!(descriptor.id, Map.get(payload, :capabilities, []))
    |> merge_roles!(descriptor.id, Map.get(payload, :roles, %{}))
    |> merge_company_directory!(descriptor, Map.get(payload, :company_directory))
  end

  defp merge_entry!(%{descriptor: descriptor}, _snapshot) do
    invalid!(descriptor.id, "payload must be a map")
  end

  defp merge_domains!(snapshot, owner, domains) when is_map(domains) do
    Enum.reduce(domains, snapshot, fn {domain, description}, acc ->
      unless valid_segment?(domain) and non_empty_string?(description) do
        invalid!(owner, "domain #{inspect(domain)} must have a valid key and description")
      end

      case Map.fetch(acc.domains, domain) do
        :error ->
          %{
            acc
            | domains: Map.put(acc.domains, domain, description),
              domain_owners: Map.put(acc.domain_owners, domain, owner)
          }

        {:ok, ^description} ->
          acc

        {:ok, existing} ->
          first_owner = Map.fetch!(acc.domain_owners, domain)

          invalid!(
            owner,
            "domain #{domain} conflicts with #{first_owner}: #{inspect(existing)}"
          )
      end
    end)
  end

  defp merge_domains!(_snapshot, owner, _domains), do: invalid!(owner, "domains must be a map")

  defp merge_verbs!(snapshot, owner, verbs) when is_list(verbs) do
    Enum.reduce(verbs, snapshot, fn verb, acc ->
      unless valid_segment?(verb), do: invalid!(owner, "invalid verb #{inspect(verb)}")

      case Map.fetch(acc.verbs, verb) do
        :error -> %{acc | verbs: Map.put(acc.verbs, verb, owner)}
        {:ok, ^owner} -> invalid!(owner, "duplicates verb #{verb}")
        {:ok, first_owner} -> invalid!(owner, "verb #{verb} is already owned by #{first_owner}")
      end
    end)
  end

  defp merge_verbs!(_snapshot, owner, _verbs), do: invalid!(owner, "verbs must be a list")

  defp merge_capabilities!(snapshot, owner, capabilities) when is_list(capabilities) do
    Enum.reduce(capabilities, snapshot, fn capability, acc ->
      unless CapabilityKey.valid?(capability) do
        invalid!(owner, "invalid capability key #{inspect(capability)}")
      end

      case Map.fetch(acc.capabilities, capability) do
        :error ->
          %{acc | capabilities: Map.put(acc.capabilities, capability, owner)}

        {:ok, first_owner} ->
          invalid!(owner, "capability #{capability} is already owned by #{first_owner}")
      end
    end)
  end

  defp merge_capabilities!(_snapshot, owner, _capabilities),
    do: invalid!(owner, "capabilities must be a list")

  defp merge_roles!(snapshot, owner, roles) when is_map(roles) do
    Enum.reduce(roles, snapshot, fn {code, definition}, acc ->
      unless is_binary(code) and Regex.match?(@role_code, code) and is_map(definition) do
        invalid!(owner, "invalid system role contribution #{inspect(code)}")
      end

      unknown_keys = Map.keys(definition) -- @role_keys

      if unknown_keys != [] do
        invalid!(owner, "role #{code} has unknown keys: #{inspect(Enum.sort(unknown_keys))}")
      end

      contribution = normalize_role!(owner, code, definition)
      merged = merge_role!(owner, code, Map.get(acc.roles, code), contribution)
      %{acc | roles: Map.put(acc.roles, code, merged)}
    end)
  end

  defp merge_roles!(_snapshot, owner, _roles), do: invalid!(owner, "roles must be a map")

  defp normalize_role!(owner, code, definition) do
    name = Map.get(definition, :name)
    description = Map.get(definition, :description)
    grant_all = Map.get(definition, :grant_all)
    capabilities = Map.get(definition, :capabilities, [])

    unless is_nil(name) or non_empty_string?(name),
      do: invalid!(owner, "role #{code} name must be non-empty")

    unless is_nil(description) or is_binary(description),
      do: invalid!(owner, "role #{code} description must be a string or nil")

    unless is_nil(grant_all) or is_boolean(grant_all),
      do: invalid!(owner, "role #{code} grant_all must be boolean")

    unless is_list(capabilities) and Enum.all?(capabilities, &CapabilityKey.valid?/1) do
      invalid!(owner, "role #{code} capabilities must be valid capability keys")
    end

    if length(capabilities) != length(Enum.uniq(capabilities)) do
      invalid!(owner, "role #{code} repeats a capability")
    end

    %{
      code: code,
      name: name,
      description: description,
      grant_all: grant_all,
      capabilities: capabilities,
      owners: [owner]
    }
  end

  defp merge_role!(_owner, _code, nil, contribution), do: contribution

  defp merge_role!(owner, code, existing, contribution) do
    %{
      code: code,
      name: merge_role_field!(owner, code, :name, existing.name, contribution.name),
      description:
        merge_role_field!(
          owner,
          code,
          :description,
          existing.description,
          contribution.description
        ),
      grant_all:
        merge_role_field!(owner, code, :grant_all, existing.grant_all, contribution.grant_all),
      capabilities: Enum.uniq(existing.capabilities ++ contribution.capabilities),
      owners: existing.owners ++ [owner]
    }
  end

  defp merge_role_field!(_owner, _code, _field, existing, nil), do: existing
  defp merge_role_field!(_owner, _code, _field, nil, contributed), do: contributed
  defp merge_role_field!(_owner, _code, _field, value, value), do: value

  defp merge_role_field!(owner, code, field, existing, contributed) do
    invalid!(
      owner,
      "role #{code} conflicts on #{field}: #{inspect(existing)} != #{inspect(contributed)}"
    )
  end

  defp merge_company_directory!(snapshot, _descriptor, nil), do: snapshot

  defp merge_company_directory!(%{company_directory: nil} = snapshot, descriptor, directory)
       when is_atom(directory) do
    validate_company_directory!(descriptor, directory)
    %{snapshot | company_directory: directory}
  end

  defp merge_company_directory!(snapshot, descriptor, directory) when is_atom(directory) do
    invalid!(
      descriptor.id,
      "company directory #{inspect(directory)} conflicts with #{inspect(snapshot.company_directory)}"
    )
  end

  defp merge_company_directory!(_snapshot, descriptor, directory) do
    invalid!(descriptor.id, "company_directory must be a module atom, got #{inspect(directory)}")
  end

  defp validate_company_directory!(descriptor, directory) do
    unless Code.ensure_loaded?(directory) do
      invalid!(descriptor.id, "company directory #{inspect(directory)} could not be loaded")
    end

    behaviours =
      directory.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    application_modules = Application.spec(descriptor.otp_app, :modules) || []

    unless CompanyDirectory in behaviours and
             function_exported?(directory, :company_ids, 1) and
             function_exported?(directory, :company_in_scope?, 2) do
      invalid!(descriptor.id, "company directory #{inspect(directory)} has the wrong contract")
    end

    unless directory in application_modules do
      invalid!(
        descriptor.id,
        "company directory #{inspect(directory)} does not belong to #{descriptor.otp_app}"
      )
    end
  end

  defp finalize!(snapshot) do
    validate_capabilities!(snapshot)

    roles = Map.new(snapshot.roles, fn {code, role} -> {code, finalize_role!(snapshot, role)} end)

    %{
      domains: snapshot.domains,
      verbs: snapshot.verbs |> Map.keys() |> Enum.sort(),
      capabilities: snapshot.capabilities |> Map.keys() |> Enum.sort(),
      capability_owners: snapshot.capabilities,
      roles: roles,
      company_directory: snapshot.company_directory
    }
  end

  defp validate_capabilities!(snapshot) do
    Enum.each(snapshot.capabilities, fn {capability, owner} ->
      parts = CapabilityKey.parse!(capability)

      unless Map.has_key?(snapshot.domains, parts.domain) do
        invalid!(owner, "capability #{capability} references unknown domain #{parts.domain}")
      end

      unless Map.has_key?(snapshot.verbs, parts.action) do
        invalid!(owner, "capability #{capability} references unknown verb #{parts.action}")
      end
    end)
  end

  defp finalize_role!(snapshot, role) do
    unless non_empty_string?(role.name) do
      invalid!(Enum.join(role.owners, ", "), "role #{role.code} has no owning name")
    end

    grant_all = role.grant_all || false
    unknown = role.capabilities -- Map.keys(snapshot.capabilities)

    if unknown != [] do
      invalid!(
        Enum.join(role.owners, ", "),
        "role #{role.code} references unknown capabilities: #{Enum.join(Enum.sort(unknown), ", ")}"
      )
    end

    if grant_all and role.capabilities != [] do
      invalid!(Enum.join(role.owners, ", "), "role #{role.code} combines grant_all and grants")
    end

    %{role | grant_all: grant_all, capabilities: Enum.sort(role.capabilities)}
  end

  defp valid_segment?(value), do: is_binary(value) and Regex.match?(@segment, value)
  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp invalid!(owner, message) do
    raise ArgumentError, "authz contribution from #{owner} #{message}"
  end
end
