defmodule Bilimbi.Base.AgentApi.InputSchema do
  @moduledoc """
  The small subset of JSON Schema an operation declares its input in, and
  the checker that holds a call's input to it.

  A schema is a string-keyed map, so it is a plain term in the contribution
  snapshot and is served to an agent exactly as declared. The keywords are:

    * `"type"`: `"object"`, `"string"`, `"integer"`, `"number"`,
      `"boolean"` or `"array"`; required on every schema;
    * `"properties"` and `"required"` on an object. An object accepts no
      property it does not declare, so a misspelt field is refused rather
      than ignored;
    * `"enum"`: the allowed values, each of the schema's type;
    * `"minimum"` and `"maximum"` on an integer or number;
    * `"maxLength"` on a string;
    * `"items"` on an array, which it requires;
    * `"format"` on a string: `"date"`, `"date-time"` or `"email"`;
    * `"description"` and `"title"`, text for the agent reading it.

  An operation's input schema is an object. Anything else, an unknown
  keyword included, fails `check_schema/1`, which the contribution
  validator calls so a malformed schema fails boot.

  This checks shape only. Whether a value makes sense for the record is the
  facade's changeset's decision, made on the facade's terms.
  """

  @types ~w(object string integer number boolean array)
  @formats ~w(date date-time email)
  @annotations ~w(description title)
  @keywords %{
    "object" => ~w(type properties required),
    "string" => ~w(type enum maxLength format),
    "integer" => ~w(type enum minimum maximum),
    "number" => ~w(type enum minimum maximum),
    "boolean" => ~w(type),
    "array" => ~w(type items)
  }
  @email ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/

  @type schema :: %{String.t() => term()}
  @type field_errors :: %{String.t() => [String.t()]}

  @doc """
  Checks that `schema` is a well-formed operation input schema: an object
  built only from the keywords above. Returns `:ok` or `{:error, reason}`.
  """
  @spec check_schema(term()) :: :ok | {:error, String.t()}
  def check_schema(%{"type" => "object"} = schema), do: check_node(schema, "input")
  def check_schema(_schema), do: {:error, "input must be an object schema"}

  @doc """
  Checks `input` against an operation's input schema.

  Returns `:ok`, or `{:error, field_errors}` keyed by the dotted path of
  each failing field (`""` for the input itself), each with its messages.
  """
  @spec validate(schema(), term()) :: :ok | {:error, field_errors()}
  def validate(schema, input) do
    case errors(schema, input, []) do
      [] ->
        :ok

      errors ->
        {:error, Enum.group_by(errors, &elem(&1, 0), &elem(&1, 1))}
    end
  end

  # Schema shape

  defp check_node(%{"type" => type} = node, path) when type in @types do
    allowed = Map.fetch!(@keywords, type) ++ @annotations

    with :ok <- known_keywords(node, allowed, path),
         :ok <- annotations(node, path),
         :ok <- check_type(type, node, path) do
      check_enum(type, node, path)
    end
  end

  defp check_node(node, path) when is_map(node),
    do: {:error, "#{path} must name a type, one of #{Enum.join(@types, ", ")}"}

  defp check_node(_node, path), do: {:error, "#{path} must be a schema map"}

  defp known_keywords(node, allowed, path) do
    case Map.keys(node) -- allowed do
      [] -> :ok
      unknown -> {:error, "#{path} has unsupported keywords #{inspect(Enum.sort(unknown))}"}
    end
  end

  defp annotations(node, path) do
    if Enum.all?(@annotations, &(not Map.has_key?(node, &1) or is_binary(node[&1]))),
      do: :ok,
      else: {:error, "#{path} description and title must be strings"}
  end

  defp check_type("object", node, path) do
    properties = Map.get(node, "properties", %{})
    required = Map.get(node, "required", [])

    cond do
      not is_map(properties) or not Enum.all?(Map.keys(properties), &is_binary/1) ->
        {:error, "#{path} properties must be a map keyed by field name"}

      not is_list(required) or not Enum.all?(required, &is_binary/1) ->
        {:error, "#{path} required must be a list of field names"}

      (missing = required -- Map.keys(properties)) != [] ->
        {:error, "#{path} requires undeclared fields #{inspect(missing)}"}

      true ->
        properties
        |> Enum.sort()
        |> Enum.reduce_while(:ok, fn {name, child}, :ok ->
          case check_node(child, join(path, name)) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  defp check_type("array", %{"items" => items}, path), do: check_node(items, path <> "[]")
  defp check_type("array", _node, path), do: {:error, "#{path} is an array without items"}

  defp check_type("string", node, path) do
    cond do
      Map.has_key?(node, "maxLength") and not non_neg_integer?(node["maxLength"]) ->
        {:error, "#{path} maxLength must be a non-negative integer"}

      Map.has_key?(node, "format") and node["format"] not in @formats ->
        {:error, "#{path} format must be one of #{Enum.join(@formats, ", ")}"}

      true ->
        :ok
    end
  end

  defp check_type(type, node, path) when type in ["integer", "number"] do
    if Enum.all?(~w(minimum maximum), &(not Map.has_key?(node, &1) or is_number(node[&1]))),
      do: :ok,
      else: {:error, "#{path} minimum and maximum must be numbers"}
  end

  defp check_type("boolean", _node, _path), do: :ok

  defp check_enum(type, %{"enum" => values}, path) do
    if is_list(values) and values != [] and Enum.all?(values, &of_type?(type, &1)),
      do: :ok,
      else: {:error, "#{path} enum must be a non-empty list of #{type} values"}
  end

  defp check_enum(_type, _node, _path), do: :ok

  # Input

  defp errors(%{"type" => type} = schema, value, path) do
    if of_type?(type, value),
      do: constraints(type, schema, value, path),
      else: [{render(path), "must be #{article(type)}"}]
  end

  defp constraints("object", schema, value, path) do
    properties = Map.get(schema, "properties", %{})
    required = Map.get(schema, "required", [])

    unknown =
      value
      |> Map.keys()
      |> Enum.reject(&(is_binary(&1) and Map.has_key?(properties, &1)))
      |> Enum.map(&{render(path ++ [to_string(&1)]), "is not a field of this operation"})

    missing =
      for name <- required,
          not Map.has_key?(value, name),
          do: {render(path ++ [name]), "is required"}

    present =
      for {name, child} <- Enum.sort(properties),
          Map.has_key?(value, name),
          error <- errors(child, Map.fetch!(value, name), path ++ [name]),
          do: error

    unknown ++ missing ++ present
  end

  defp constraints("array", %{"items" => items}, value, path) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> errors(items, item, path ++ ["#{index}"]) end)
  end

  defp constraints(_type, schema, value, path) do
    [
      enum_error(schema, value),
      bound_error(schema, value, "minimum", &>=/2, "must be at least"),
      bound_error(schema, value, "maximum", &<=/2, "must be at most"),
      length_error(schema, value),
      format_error(schema, value)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&{render(path), &1})
  end

  defp enum_error(%{"enum" => values}, value) do
    if value in values, do: nil, else: "must be one of #{Enum.map_join(values, ", ", &"#{&1}")}"
  end

  defp enum_error(_schema, _value), do: nil

  defp bound_error(schema, value, keyword, holds?, message) do
    case Map.fetch(schema, keyword) do
      {:ok, bound} -> if holds?.(value, bound), do: nil, else: "#{message} #{bound}"
      :error -> nil
    end
  end

  defp length_error(%{"maxLength" => max}, value) do
    if String.length(value) <= max, do: nil, else: "must be at most #{max} characters"
  end

  defp length_error(_schema, _value), do: nil

  defp format_error(%{"format" => "date"}, value),
    do: if(match?({:ok, _}, Date.from_iso8601(value)), do: nil, else: "must be a date")

  defp format_error(%{"format" => "date-time"}, value) do
    if match?({:ok, _, _}, DateTime.from_iso8601(value)),
      do: nil,
      else: "must be a date and time with an offset"
  end

  defp format_error(%{"format" => "email"}, value),
    do: if(Regex.match?(@email, value), do: nil, else: "must be an email address")

  defp format_error(_schema, _value), do: nil

  defp of_type?("object", value), do: is_map(value) and not is_struct(value)
  defp of_type?("string", value), do: is_binary(value)
  defp of_type?("integer", value), do: is_integer(value)
  defp of_type?("number", value), do: is_number(value)
  defp of_type?("boolean", value), do: is_boolean(value)
  defp of_type?("array", value), do: is_list(value)

  defp article("object"), do: "an object"
  defp article("integer"), do: "an integer"
  defp article("array"), do: "an array"
  defp article(type), do: "a #{type}"

  defp non_neg_integer?(value), do: is_integer(value) and value >= 0

  defp join(path, name), do: "#{path}.#{name}"
  defp render(path), do: Enum.join(path, ".")
end
