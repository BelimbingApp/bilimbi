defmodule Bilimbi.Base.AgentApi.ContributionValidatorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.AgentApi.ContributionValidator
  alias Bilimbi.Base.AgentApi.Definition
  alias Bilimbi.Base.AgentApi.Guide
  alias Bilimbi.Base.AgentApi.TestFixtures
  alias Bilimbi.Base.AgentApi.TestOperations

  defp validate(payload), do: ContributionValidator.validate_contributions!([entry(payload)])
  defp entry(payload), do: %{descriptor: TestFixtures.descriptor(), payload: payload}

  defp operation(key), do: Enum.find(TestOperations.payload().operations, &(&1.key == key))

  defp get_operation(overrides \\ %{}),
    do: Map.merge(operation("base.agent_api.record.get"), overrides)

  defp write_operation(overrides),
    do: Map.merge(operation("base.agent_api.record.update"), overrides)

  defp refused(payload, message) do
    assert_raise ArgumentError, message, fn -> validate(payload) end
  end

  test "an empty contribution set is an empty registry" do
    assert ContributionValidator.validate_contributions!([]) == %{operations: %{}, guides: %{}}
  end

  test "the test domain validates into operations and guides keyed by key" do
    %{operations: operations, guides: guides} = validate(TestOperations.payload())

    assert operations |> Map.keys() |> Enum.sort() ==
             ~w(base.agent_api.record.get base.agent_api.record.list base.agent_api.record.update)

    assert %Definition{
             owner: "base/agent_api",
             kind: :read,
             approval: nil,
             capability: "admin.test.record.view",
             keywords: ["show", "detail"]
           } = operations["base.agent_api.record.get"]

    assert %Definition{kind: :write, approval: :level, keywords: []} =
             operations["base.agent_api.record.update"]

    # An operation that describes no output gets an object.
    assert operations["base.agent_api.record.list"].output == %{"type" => "object"}
    assert %Guide{owner: "base/agent_api", keywords: []} = guides["base.agent_api.record"]
  end

  test "a key declared twice, by one module or by two, is refused naming both" do
    refused(
      %{operations: [get_operation(), get_operation()]},
      ~r/duplicate agent_api keys: base.agent_api.record.get declared by base\/agent_api, base\/agent_api/
    )

    assert_raise ArgumentError, ~r/duplicate agent_api keys: base.agent_api.record.get/, fn ->
      ContributionValidator.validate_contributions!([
        entry(%{operations: [get_operation()]}),
        entry(%{operations: [get_operation()]})
      ])
    end
  end

  test "a key must begin with its owner's id" do
    refused(
      %{operations: [get_operation(%{key: "core.company.get"})]},
      ~r/key must begin with its owner's id, base.agent_api\./
    )

    refused(
      %{operations: [get_operation(%{key: "Base.Agent_api.Get"})]},
      ~r/key must be lowercase dotted segments/
    )
  end

  test "a handler from another OTP application is refused" do
    refused(
      %{operations: [get_operation(%{handler: Bilimbi.Base.Authz})]},
      ~r/handler Bilimbi.Base.Authz does not belong to :bilimbi_base_agent_api/
    )
  end

  test "a handler that does not implement the Operation behaviour is refused" do
    refused(
      %{operations: [get_operation(%{handler: Bilimbi.Base.AgentApi.TestNotAnOperation})]},
      ~r/does not implement Bilimbi.Base.AgentApi.Operation/
    )

    refused(
      %{operations: [get_operation(%{handler: Bilimbi.Base.AgentApi.NoSuchHandler})]},
      ~r/handler Bilimbi.Base.AgentApi.NoSuchHandler could not be loaded/
    )
  end

  test "a malformed input schema is refused, saying what is wrong" do
    for {input, message} <- [
          {%{"type" => "string"}, ~r/input must be an object schema/},
          {%{type: "object"}, ~r/input must be an object schema/},
          {%{"type" => "object", "additionalProperties" => true},
           ~r/input has unsupported keywords \["additionalProperties"\]/},
          {%{"type" => "object", "required" => ["id"]}, ~r/requires undeclared fields \["id"\]/},
          {%{"type" => "object", "properties" => %{"id" => %{"type" => "uuid"}}},
           ~r/input.id must name a type/},
          {%{"type" => "object", "properties" => %{"tags" => %{"type" => "array"}}},
           ~r/input.tags is an array without items/},
          {%{
             "type" => "object",
             "properties" => %{"at" => %{"type" => "string", "format" => "uri"}}
           }, ~r/input.at format must be one of date, date-time, email/},
          {%{
             "type" => "object",
             "properties" => %{"n" => %{"type" => "integer", "maxLength" => 3}}
           }, ~r/input.n has unsupported keywords \["maxLength"\]/},
          {%{"type" => "object", "properties" => %{"s" => %{"type" => "string", "enum" => [1]}}},
           ~r/input.s enum must be a non-empty list of string values/}
        ] do
      refused(%{operations: [get_operation(%{input: input})]}, message)
    end
  end

  test "a write whose handler exports no preview/3 is refused" do
    refused(
      %{operations: [write_operation(%{handler: Bilimbi.Base.AgentApi.TestReadOnlyHandler})]},
      ~r/is a write and its handler does not export preview\/3/
    )
  end

  test "an operation on an access-control capability is refused, a write or a read" do
    for capability <-
          ~w(admin.authz.role.update admin.user.impersonate base.settings.company.manage
                         admin.agent-connection.revoke) do
      refused(
        %{operations: [write_operation(%{capability: capability})]},
        ~r/stands on #{Regex.escape(capability)}, an access-control capability no agent may hold/
      )
    end

    refused(
      %{operations: [get_operation(%{capability: "admin.authz.role.view"})]},
      ~r/an access-control capability/
    )

    refused(
      %{
        guides: [
          %{
            key: "base.agent_api",
            title: "T",
            summary: "S",
            body: "B",
            capability: "admin.authz.role.list"
          }
        ]
      },
      ~r/an access-control capability/
    )
  end

  test "a read must stand on a read capability, and only a write declares approval" do
    refused(
      %{operations: [get_operation(%{capability: "admin.test.record.update"})]},
      ~r/is a read but its capability admin.test.record.update does not end in a read verb/
    )

    refused(
      %{operations: [get_operation(%{approval: :level})]},
      ~r/is a read and declares no approval/
    )

    refused(
      %{operations: [write_operation(%{approval: :sometimes})]},
      ~r/must declare approval :level or :required/
    )

    refused(%{operations: [get_operation(%{kind: :delete})]}, ~r/kind must be :read or :write/)
  end

  test "fields are exact: unknown ones and missing ones are refused" do
    refused(%{operations: [get_operation(%{route: "/x"})]}, ~r/has unknown fields \[:route\]/)

    refused(
      %{operations: [Map.delete(get_operation(), :capability)]},
      ~r/is missing \[:capability\]/
    )

    refused(
      %{widgets: []},
      ~r/must be %\{operations: \[operation maps\], guides: \[guide maps\]\}/
    )
  end

  test "a guide's body is at most 8 KB and its key may be the owner's own" do
    guide = %{
      key: "base.agent_api",
      title: "Agent API",
      summary: "About it",
      capability: "admin.test.record.list",
      body: String.duplicate("a", 8 * 1024)
    }

    assert %{guides: %{"base.agent_api" => %Guide{}}} = validate(%{guides: [guide]})

    refused(
      %{guides: [%{guide | body: String.duplicate("a", 8 * 1024 + 1)}]},
      ~r/body must be non-empty text of at most 8192 bytes/
    )
  end
end
