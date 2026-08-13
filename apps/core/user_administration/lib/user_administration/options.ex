defmodule Bilimbi.Core.UserAdministration.Options do
  @moduledoc false

  @allowed_keys [:search, :role_ids, :sort_by, :sort_dir, :page, :page_size]
  @page_sizes [10, 25, 50, 100]
  @sort_fields [:name, :email, :company_name, :created_at]
  @sort_directions [:asc, :desc]
  @maximum_search_bytes 255
  @maximum_role_ids 100

  @enforce_keys [:search, :role_ids, :sort_by, :sort_dir, :page, :page_size]
  defstruct search: nil,
            role_ids: [],
            sort_by: :name,
            sort_dir: :asc,
            page: 1,
            page_size: 25

  @type t :: %__MODULE__{
          search: nil | binary(),
          role_ids: [pos_integer()],
          sort_by: :name | :email | :company_name | :created_at,
          sort_dir: :asc | :desc,
          page: pos_integer(),
          page_size: 10 | 25 | 50 | 100
        }

  @spec new!(keyword()) :: t()
  def new!(options) when is_list(options) do
    if not Keyword.keyword?(options) do
      raise ArgumentError, "options must be a keyword list"
    end

    reject_unknown_keys!(options)
    reject_duplicate_keys!(options)

    %__MODULE__{
      search: search!(Keyword.get(options, :search)),
      role_ids: role_ids!(Keyword.get(options, :role_ids, [])),
      sort_by: member!(Keyword.get(options, :sort_by, :name), @sort_fields, :sort_by),
      sort_dir: member!(Keyword.get(options, :sort_dir, :asc), @sort_directions, :sort_dir),
      page: positive_integer!(Keyword.get(options, :page, 1), :page),
      page_size: member!(Keyword.get(options, :page_size, 25), @page_sizes, :page_size)
    }
  end

  def new!(_options), do: raise(ArgumentError, "options must be a keyword list")

  defp reject_unknown_keys!(options) do
    case Keyword.keys(options) -- @allowed_keys do
      [] -> :ok
      keys -> raise ArgumentError, "unknown options: #{inspect(Enum.uniq(keys))}"
    end
  end

  defp reject_duplicate_keys!(options) do
    keys = Keyword.keys(options)

    if length(keys) != length(Enum.uniq(keys)) do
      raise ArgumentError, "options must not repeat keys"
    end
  end

  defp search!(nil), do: nil
  defp search!(""), do: nil
  defp search!("0"), do: nil

  defp search!(value) when is_binary(value) and byte_size(value) <= @maximum_search_bytes,
    do: value

  defp search!(value) do
    raise ArgumentError,
          "search must be nil or a binary no longer than #{@maximum_search_bytes} bytes, got: #{inspect(value)}"
  end

  defp role_ids!(role_ids) when is_list(role_ids) do
    if length(role_ids) > @maximum_role_ids or
         Enum.any?(role_ids, &(not is_integer(&1) or &1 <= 0)) or
         length(role_ids) != length(Enum.uniq(role_ids)) do
      raise ArgumentError,
            "role_ids must contain at most #{@maximum_role_ids} unique positive integer IDs"
    end

    role_ids
  end

  defp role_ids!(_role_ids) do
    raise ArgumentError,
          "role_ids must contain at most #{@maximum_role_ids} unique positive integer IDs"
  end

  defp member!(value, allowed, name) do
    if value in allowed do
      value
    else
      raise ArgumentError, "#{name} must be one of #{inspect(allowed)}, got: #{inspect(value)}"
    end
  end

  defp positive_integer!(value, _name) when is_integer(value) and value > 0, do: value

  defp positive_integer!(value, name) do
    raise ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}"
  end
end
