defmodule Bilimbi.Base.AgentApi.ContributionValidator do
  @moduledoc """
  Validates every installed module's `:agent_api` contribution into one
  registry of operations and guides (ADR 0021).

  This is how a module exposes its work to agents. A contribution is
  `%{operations: [operation_map], guides: [guide_map]}`, either list
  optional:

  ```elixir
  agent_api: %{
    operations: [
      %{
        key: "core.company.get",
        title: "Read a company",
        summary: "One company of your tenant by id, with the fields you may see.",
        keywords: ["organisation", "business"],
        kind: :read,
        capability: "admin.company.view",
        input: %{
          "type" => "object",
          "required" => ["company_id"],
          "properties" => %{"company_id" => %{"type" => "integer", "minimum" => 1}}
        },
        handler: Bilimbi.Core.Company.AgentOperations
      }
    ],
    guides: [
      %{key: "core.company", title: "Companies", summary: "...",
        capability: "admin.company.list", body: "Markdown, at most 8 KB."}
    ]
  }
  ```

  The rules, each of which fails the snapshot and with it boot:

    * a key is lowercase dotted segments that begin with the owner's id,
      `/` read as `.` (`core.company.` for `core/company`), and is unique
      across every module's operations and guides. A guide's key may be
      the owner prefix itself;
    * `kind` is `:read` or `:write`. A write declares `approval`, `:level`
      (it runs at once for a connection allowed to write) or `:required`
      (a person always approves it); a read declares none;
    * `capability` is a well-formed capability key: the one the matching
      screen's route or event asks for. A read operation stands on a read
      capability, and no operation or guide stands on an access-control
      capability (`Bilimbi.Base.AgentApi.Reach`). Whether the capability is
      registered is checked against the Authz registry by the host, because
      a validator sees only its own consumer's entries;
    * `input` is a well-formed `Bilimbi.Base.AgentApi.InputSchema` object,
      and `output`, when given, is a string-keyed map;
    * `handler` belongs to the declaring module's OTP application and
      implements `Bilimbi.Base.AgentApi.Operation`, and a write's handler
      exports `preview/3`. No module can expose another module's code under
      its own name, the rule ADR 0019 set for grid sources;
    * a guide's `body` is at most 8 KB.

  A module that is not installed contributes nothing, so its operations do
  not exist. No module adds a route for its operations: the host serves
  them all.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.AgentApi.Definition
  alias Bilimbi.Base.AgentApi.Guide
  alias Bilimbi.Base.AgentApi.InputSchema
  alias Bilimbi.Base.AgentApi.Operation
  alias Bilimbi.Base.AgentApi.Reach
  alias Bilimbi.Base.Authz.CapabilityKey

  @type registry :: %{
          operations: %{String.t() => Definition.t()},
          guides: %{String.t() => Guide.t()}
        }

  @segment "[a-z0-9][a-z0-9_-]*"
  @key_pattern Regex.compile!("^#{@segment}(?:\\.#{@segment})+$")
  @operation_keys [
    :key,
    :title,
    :summary,
    :keywords,
    :kind,
    :capability,
    :approval,
    :input,
    :output,
    :handler
  ]
  @operation_required [:key, :title, :summary, :kind, :capability, :input, :handler]
  @guide_keys [:key, :title, :summary, :keywords, :capability, :body]
  @guide_required [:key, :title, :summary, :capability, :body]
  @max_title 120
  @max_summary 500
  @max_body 8 * 1024

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: registry()
  def validate_contributions!(entries) when is_list(entries) do
    {operations, guides} =
      Enum.reduce(entries, {[], []}, fn entry, {operations, guides} ->
        {entry_operations, entry_guides} = entry!(entry)
        {operations ++ entry_operations, guides ++ entry_guides}
      end)

    reject_duplicate_keys!(operations ++ guides)

    %{
      operations: Map.new(operations, &{&1.key, &1}),
      guides: Map.new(guides, &{&1.key, &1})
    }
  end

  defp entry!(%{descriptor: descriptor, payload: payload}) do
    unless is_map(payload) and Map.keys(payload) -- [:operations, :guides] == [] and
             is_list(Map.get(payload, :operations, [])) and
             is_list(Map.get(payload, :guides, [])) do
      raise ArgumentError,
            "agent_api contribution from #{descriptor.id} must be " <>
              "%{operations: [operation maps], guides: [guide maps]}"
    end

    {
      payload |> Map.get(:operations, []) |> Enum.map(&operation!(&1, descriptor)),
      payload |> Map.get(:guides, []) |> Enum.map(&guide!(&1, descriptor))
    }
  end

  defp operation!(attrs, descriptor) do
    attrs = fields!(attrs, @operation_keys, @operation_required, descriptor, "operation")
    key = key!(attrs.key, descriptor, :operation)
    kind = kind!(attrs.kind, key, descriptor)
    capability = capability!(attrs.capability, key, descriptor)

    if kind == :read and not Reach.read?(capability) do
      invalid!(
        descriptor,
        key,
        "is a read but its capability #{capability} does not end in a read verb " <>
          "(#{Enum.join(Reach.read_verbs(), ", ")})"
      )
    end

    %Definition{
      key: key,
      owner: descriptor.id,
      title: text!(attrs.title, :title, @max_title, key, descriptor),
      summary: text!(attrs.summary, :summary, @max_summary, key, descriptor),
      keywords: keywords!(Map.get(attrs, :keywords, []), key, descriptor),
      kind: kind,
      capability: capability,
      approval: approval!(kind, Map.get(attrs, :approval), key, descriptor),
      input: input!(attrs.input, key, descriptor),
      output: output!(Map.get(attrs, :output, %{"type" => "object"}), key, descriptor),
      handler: handler!(attrs.handler, kind, key, descriptor)
    }
  end

  defp guide!(attrs, descriptor) do
    attrs = fields!(attrs, @guide_keys, @guide_required, descriptor, "guide")
    key = key!(attrs.key, descriptor, :guide)

    unless is_binary(attrs.body) and byte_size(attrs.body) in 1..@max_body do
      invalid!(descriptor, key, "body must be non-empty text of at most #{@max_body} bytes")
    end

    %Guide{
      key: key,
      owner: descriptor.id,
      title: text!(attrs.title, :title, @max_title, key, descriptor),
      summary: text!(attrs.summary, :summary, @max_summary, key, descriptor),
      keywords: keywords!(Map.get(attrs, :keywords, []), key, descriptor),
      capability: capability!(attrs.capability, key, descriptor),
      body: attrs.body
    }
  end

  defp fields!(attrs, allowed, required, descriptor, noun) do
    unless is_map(attrs) do
      raise ArgumentError,
            "agent_api contribution from #{descriptor.id} must contain #{noun} maps"
    end

    label = Map.get(attrs, :key, "without a key")

    case Map.keys(attrs) -- allowed do
      [] -> :ok
      unknown -> invalid!(descriptor, label, "has unknown fields #{inspect(Enum.sort(unknown))}")
    end

    case required -- Map.keys(attrs) do
      [] -> attrs
      missing -> invalid!(descriptor, label, "is missing #{inspect(missing)}")
    end
  end

  defp key!(key, descriptor, type) do
    prefix = String.replace(descriptor.id, "/", ".")

    unless is_binary(key) and Regex.match?(@key_pattern, key) do
      invalid!(descriptor, key, "key must be lowercase dotted segments")
    end

    owned? =
      String.starts_with?(key, prefix <> ".") or (type == :guide and key == prefix)

    unless owned? do
      invalid!(descriptor, key, "key must begin with its owner's id, #{prefix}.")
    end

    key
  end

  defp kind!(kind, _key, _descriptor) when kind in [:read, :write], do: kind

  defp kind!(_kind, key, descriptor),
    do: invalid!(descriptor, key, "kind must be :read or :write")

  defp approval!(:read, nil, _key, _descriptor), do: nil

  defp approval!(:read, _approval, key, descriptor),
    do: invalid!(descriptor, key, "is a read and declares no approval")

  defp approval!(:write, approval, _key, _descriptor) when approval in [:level, :required],
    do: approval

  defp approval!(:write, _approval, key, descriptor),
    do: invalid!(descriptor, key, "is a write and must declare approval :level or :required")

  defp capability!(capability, key, descriptor) do
    cond do
      not CapabilityKey.valid?(capability) ->
        invalid!(descriptor, key, "capability #{inspect(capability)} is not a capability key")

      Reach.access_control?(capability) ->
        invalid!(
          descriptor,
          key,
          "stands on #{capability}, an access-control capability no agent may hold"
        )

      true ->
        capability
    end
  end

  defp text!(text, field, max, key, descriptor) do
    if is_binary(text) and String.trim(text) != "" and String.length(text) <= max,
      do: text,
      else:
        invalid!(descriptor, key, "#{field} must be non-empty text of at most #{max} characters")
  end

  defp keywords!(keywords, key, descriptor) do
    if is_list(keywords) and Enum.all?(keywords, &(is_binary(&1) and String.trim(&1) != "")),
      do: keywords,
      else: invalid!(descriptor, key, "keywords must be a list of non-empty strings")
  end

  defp input!(schema, key, descriptor) do
    case InputSchema.check_schema(schema) do
      :ok -> schema
      {:error, reason} -> invalid!(descriptor, key, "has a malformed input schema: #{reason}")
    end
  end

  defp output!(schema, key, descriptor) do
    if is_map(schema) and Enum.all?(Map.keys(schema), &is_binary/1),
      do: schema,
      else: invalid!(descriptor, key, "output must be a string-keyed schema map")
  end

  defp handler!(handler, kind, key, descriptor) do
    cond do
      not (is_atom(handler) and Code.ensure_loaded?(handler)) ->
        invalid!(descriptor, key, "handler #{inspect(handler)} could not be loaded")

      handler not in (Application.spec(descriptor.otp_app, :modules) || []) ->
        invalid!(
          descriptor,
          key,
          "handler #{inspect(handler)} does not belong to #{inspect(descriptor.otp_app)}"
        )

      Operation not in behaviours(handler) ->
        invalid!(
          descriptor,
          key,
          "handler #{inspect(handler)} does not implement #{inspect(Operation)}"
        )

      kind == :write and not function_exported?(handler, :preview, 3) ->
        invalid!(descriptor, key, "is a write and its handler does not export preview/3")

      true ->
        handler
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp reject_duplicate_keys!(declarations) do
    declarations
    |> Enum.group_by(& &1.key)
    |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
    |> case do
      [] ->
        :ok

      duplicates ->
        detail =
          Enum.map_join(duplicates, "; ", fn {key, group} ->
            "#{key} declared by #{Enum.map_join(group, ", ", & &1.owner)}"
          end)

        raise ArgumentError, "duplicate agent_api keys: #{detail}"
    end
  end

  defp invalid!(descriptor, key, message) do
    raise ArgumentError,
          "invalid agent_api contribution from #{descriptor.id} (#{inspect(key)}): #{message}"
  end
end
