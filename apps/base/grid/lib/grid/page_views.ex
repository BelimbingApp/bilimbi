defmodule Bilimbi.Base.Grid.PageViews do
  @moduledoc """
  What each account last arranged on each list page: the columns in order,
  the lens of each, the density of the rows and the date a change-since
  lens compares against. A list opens the way its reader left it.

  The arrangements live in the account's `ui.grid.page_columns` setting at
  user scope, one plain JSON entry per page:

      %{"page" => "users",
        "view" => %{"columns" => ["name", "company.name"], "lenses" => %{},
                    "density" => "compact", "since" => nil}}

  A page is named by the catalog table its rows come from. A view that is
  the page's own, with nothing arranged, is not kept: its entry is removed,
  so the setting holds only what differs from a default. Every write goes
  through the Repo and is audited like any other, and an arrangement equal
  to the one stored writes nothing.
  """

  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope

  @key "ui.grid.page_columns"

  @doc "The setting key."
  @spec key() :: String.t()
  def key, do: @key

  @doc "The view this account last arranged on `page`, if it arranged one."
  @spec fetch(Scope.t(), String.t()) :: {:ok, View.t()} | :error
  def fetch(%Scope{type: :user} = scope, page) when is_binary(page) do
    case Enum.find(read(scope), &(&1["page"] == page)) do
      %{"view" => view} -> {:ok, View.from_map(view, page)}
      nil -> :error
    end
  end

  @doc """
  Keeps `view` as the account's arrangement of its page (`view.table`), or
  forgets the page when the view is the page's own.
  """
  @spec remember(Scope.t(), View.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def remember(%Scope{type: :user} = scope, %View{table: page} = view) when is_binary(page) do
    entries = read(scope)
    others = Enum.reject(entries, &(&1["page"] == page))

    updated =
      if View.default?(view),
        do: others,
        else: others ++ [%{"page" => page, "view" => View.to_map(view)}]

    if updated == entries do
      :ok
    else
      case Settings.put(@key, updated, scope) do
        {:ok, _stored} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp read(scope) do
    case Settings.get(@key, scope) do
      entries when is_list(entries) -> Enum.filter(entries, &entry?/1)
      _other -> []
    end
  end

  defp entry?(%{"page" => page, "view" => view}) when is_binary(page) and is_map(view), do: true
  defp entry?(_other), do: false
end
