defmodule Bilimbi.Base.Tiling.Layout do
  @moduledoc """
  The pure dwindle and master trees behind a tiled workspace.

  A layout is a binary space partition: a leaf is one tile showing a page at
  a path, and a split divides its rectangle between two children along one
  axis at a ratio. Opening a page splits a tile, and the split direction
  follows the shape of the rectangle being split (wider than tall splits
  side by side), which is what makes the tiling automatic. This is
  Hyprland's dwindle layout with the browser tab as the monitor.

  There is no cap on the number of tiles: the operator decides, and a
  control-room screen holds more than a laptop. Each tile is a live page,
  so the host documents the cost rather than this module bounding it.

  Nothing here touches a process, a socket or a page. The host LiveView owns
  focus, monocle and persistence; this module owns the shape and every
  operation on it, so each one is a value-in, value-out function that the
  tests exercise without a browser.

  Every leaf and split carries a stable id. The host renders one DOM element
  per id, so a tile's frame keeps its element across splits, closes and
  resizes and is never re-created by a re-render, which would reload the page
  inside it. `reconcile/2` keeps those ids when a tree arrives from the URL.

  The URL form is compact and readable rather than encoded:

      h.5(/companies,v.6(/employees,/users))

  `h` splits side by side and `v` top and bottom, the number is the first
  child's share, and a leaf is its path with `(`, `)`, `,`, `>` and `%`
  percent-encoded. A leaf that follows selections carries the route
  pattern it follows after `>`:

      h.5(/companies,/companies/42>/companies/:id)

  The host reads the pattern's owning module from the route manifest and
  fills its one `:param` with the id another tile announces; this module
  only keeps the pattern's shape.
  """

  @min_ratio 0.1
  @max_ratio 0.9
  @resize_step 0.05

  defstruct root: nil, next_id: 1

  @type direction :: :h | :v
  @type side :: :left | :right | :up | :down
  @type leaf :: %{type: :leaf, id: String.t(), path: String.t(), follow: String.t() | nil}
  @type split :: %{
          type: :split,
          id: String.t(),
          direction: direction(),
          ratio: float(),
          first: node_t(),
          second: node_t()
        }
  @type node_t :: leaf() | split()
  @type rect :: %{x: float(), y: float(), w: float(), h: float()}
  @type t :: %__MODULE__{root: node_t() | nil, next_id: pos_integer()}

  @doc "A workspace with no tile."
  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @doc "Whether the workspace holds no tile."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{root: nil}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc "The leaves in tree order: left before right, top before bottom."
  @spec leaves(t()) :: [leaf()]
  def leaves(%__MODULE__{root: nil}), do: []
  def leaves(%__MODULE__{root: root}), do: collect_leaves(root)

  defp collect_leaves(%{type: :leaf} = leaf), do: [leaf]

  defp collect_leaves(%{type: :split, first: first, second: second}),
    do: collect_leaves(first) ++ collect_leaves(second)

  @doc "How many tiles the workspace holds."
  @spec count(t()) :: non_neg_integer()
  def count(layout), do: length(leaves(layout))

  @doc """
  Arranges the existing tiles as one master and an evenly divided stack.

  The first tile becomes master. Existing leaf ids survive so changing modes
  never reloads a frame. Rebuilding a master tree keeps its orientation and
  master share, including after a divider drag.
  """
  @spec master(t()) :: t()
  def master(%__MODULE__{} = layout), do: master_rebuild(layout, leaves(layout))

  @doc "Whether the tree is already one master beside a single-axis stack."
  @spec master?(t()) :: boolean()
  def master?(%__MODULE__{root: root}) do
    case root do
      nil ->
        true

      %{type: :leaf} ->
        true

      %{type: :split, first: %{type: :leaf}} = split ->
        stack?(split.second, other_axis(split.direction))

      _other ->
        false
    end
  end

  defp stack?(%{type: :leaf}, _direction), do: true

  defp stack?(
         %{type: :split, direction: direction, first: %{type: :leaf}, second: second},
         direction
       ),
       do: stack?(second, direction)

  defp stack?(_node, _direction), do: false

  defp master_rebuild(layout, tiles) do
    case tiles do
      [] ->
        %{layout | root: nil}

      [leaf] ->
        %{layout | root: leaf}

      [first | stack] ->
        {direction, ratio} = master_shape(layout.root)
        {stack_root, layout} = master_stack(stack, other_axis(direction), layout)
        {id, layout} = master_root_id(layout)

        %{
          layout
          | root: %{
              type: :split,
              id: id,
              direction: direction,
              ratio: ratio,
              first: first,
              second: stack_root
            }
        }
    end
  end

  @doc "Opens a tile at the end of the master stack."
  @spec master_open(t(), String.t()) :: {:ok, t(), String.t()}
  def master_open(%__MODULE__{} = layout, path) when is_binary(path) and path != "" do
    {leaf, layout} = new_leaf(layout, path)
    {:ok, master_rebuild(layout, leaves(layout) ++ [leaf]), leaf.id}
  end

  @doc "Closes a master tile and divides the remaining stack evenly."
  @spec master_close(t(), String.t()) :: t()
  def master_close(%__MODULE__{} = layout, id) do
    if fetch_leaf(layout, id) do
      master_rebuild(layout, Enum.reject(leaves(layout), &(&1.id == id)))
    else
      layout
    end
  end

  @doc "Turns a side-by-side master into a top-and-bottom master, or back."
  @spec toggle_master_orientation(t()) :: t()
  def toggle_master_orientation(%__MODULE__{root: root} = layout),
    do: %{layout | root: flip(root)}

  defp flip(%{type: :split} = split),
    do: %{
      split
      | direction: other_axis(split.direction),
        first: flip(split.first),
        second: flip(split.second)
    }

  defp flip(node), do: node

  @doc "Makes the named tile master by exchanging it with the first tile."
  @spec promote_master(t(), String.t()) :: t()
  def promote_master(%__MODULE__{} = layout, id) do
    case leaves(layout) do
      [first | _] -> swap(layout, first.id, id)
      [] -> layout
    end
  end

  defp master_shape(%{type: :split, first: %{type: :leaf}, direction: direction, ratio: ratio}),
    do: {direction, ratio}

  defp master_shape(_root), do: {:h, 0.55}

  defp master_root_id(%__MODULE__{root: %{type: :split, id: id}} = layout),
    do: {id, layout}

  defp master_root_id(layout), do: next_id(layout, "s")

  defp master_stack([leaf], _direction, layout), do: {leaf, layout}

  defp master_stack([first | rest] = leaves, direction, layout) do
    {second, layout} = master_stack(rest, direction, layout)
    {id, layout} = next_id(layout, "s")

    {%{
       type: :split,
       id: id,
       direction: direction,
       ratio: 1 / length(leaves),
       first: first,
       second: second
     }, layout}
  end

  defp other_axis(:h), do: :v
  defp other_axis(:v), do: :h

  @doc "The leaf with this id, or nil."
  @spec fetch_leaf(t(), String.t()) :: leaf() | nil
  def fetch_leaf(layout, id), do: Enum.find(leaves(layout), &(&1.id == id))

  @doc """
  Opens `path` in a new tile.

  With an empty workspace the tile fills it. Otherwise the tile at `:at` is
  split, and the direction comes from the shape of that tile on a viewport
  of `:viewport` pixels (default: a landscape screen): wider than tall
  splits side by side, otherwise top and bottom. The new tile is the second
  child, so it appears to the right or below.

  `:at` is a tile id, or `:largest` for the tile with the most room, ties
  going to the later one in tree order. That is the dwindle order a person
  expects from the sidebar: the second page takes the right half, the third
  the bottom of that half, the fourth the bottom of the left half, and so
  on, so the screen stays balanced however many pages are open. The
  default is the last tile in tree order.

  Returns the new layout and the new tile's id.
  """
  @spec open(t(), String.t(), keyword()) :: {t(), String.t()}
  def open(%__MODULE__{} = layout, path, opts \\ []) when is_binary(path) and path != "" do
    if is_nil(layout.root) do
      {leaf, layout} = new_leaf(layout, path)
      {%{layout | root: leaf}, leaf.id}
    else
      {vw, vh} = Keyword.get(opts, :viewport, {1600, 900})
      rects = leaf_rects(layout)
      target = target(layout, rects, Keyword.get(opts, :at), {vw, vh})
      rect = Map.fetch!(rects, target)
      direction = if rect.w * vw >= rect.h * vh, do: :h, else: :v

      {leaf, layout} = new_leaf(layout, path)
      {split_id, layout} = next_id(layout, "s")

      root =
        map_node(layout.root, target, fn existing ->
          %{
            type: :split,
            id: split_id,
            direction: direction,
            ratio: 0.5,
            first: existing,
            second: leaf
          }
        end)

      {%{layout | root: root}, leaf.id}
    end
  end

  defp target(layout, rects, :largest, {vw, vh}) do
    layout
    |> leaves()
    |> Enum.with_index()
    |> Enum.max_by(fn {leaf, index} ->
      rect = Map.fetch!(rects, leaf.id)
      {Float.round(rect.w * vw * rect.h * vh, 3), index}
    end)
    |> elem(0)
    |> Map.fetch!(:id)
  end

  defp target(layout, rects, at, _viewport) do
    if is_binary(at) and Map.has_key?(rects, at), do: at, else: List.last(leaves(layout)).id
  end

  @doc """
  Closes the tile with `id`. Its sibling takes the whole of their parent's
  rectangle. Closing the only tile empties the workspace; an unknown id
  changes nothing.
  """
  @spec close(t(), String.t()) :: t()
  def close(%__MODULE__{root: nil} = layout, _id), do: layout

  def close(%__MODULE__{root: %{type: :leaf, id: id}} = layout, id), do: %{layout | root: nil}

  def close(%__MODULE__{root: root} = layout, id), do: %{layout | root: remove_leaf(root, id)}

  defp remove_leaf(%{type: :leaf} = leaf, _id), do: leaf

  defp remove_leaf(%{type: :split, first: %{type: :leaf, id: id}, second: second}, id),
    do: second

  defp remove_leaf(%{type: :split, first: first, second: %{type: :leaf, id: id}}, id),
    do: first

  defp remove_leaf(%{type: :split} = split, id) do
    %{split | first: remove_leaf(split.first, id), second: remove_leaf(split.second, id)}
  end

  @doc "Changes the path a tile shows, keeping its id, place and follow."
  @spec update_path(t(), String.t(), String.t()) :: t()
  def update_path(%__MODULE__{root: nil} = layout, _id, _path), do: layout

  def update_path(%__MODULE__{root: root} = layout, id, path) when is_binary(path) do
    %{layout | root: map_node(root, id, &%{&1 | path: path})}
  end

  @doc """
  Marks the tile with `id` as following the route `pattern`, such as
  `/companies/:id`, or clears it with `nil`. A pattern is a page path with
  exactly one `:param` segment; anything else leaves the tree unchanged.
  """
  @spec follow(t(), String.t(), String.t() | nil) :: t()
  def follow(%__MODULE__{root: nil} = layout, _id, _pattern), do: layout

  def follow(%__MODULE__{root: root} = layout, id, pattern)
      when is_nil(pattern) or is_binary(pattern) do
    if is_nil(pattern) or follow_pattern?(pattern),
      do: %{layout | root: map_node(root, id, &%{&1 | follow: pattern})},
      else: layout
  end

  @doc "Whether `pattern` is a page path with exactly one `:param` segment."
  @spec follow_pattern?(term()) :: boolean()
  def follow_pattern?(pattern) when is_binary(pattern) do
    page_path?(pattern) and not String.contains?(pattern, "?") and
      pattern |> String.split("/", trim: true) |> Enum.count(&String.starts_with?(&1, ":")) == 1
  end

  def follow_pattern?(_pattern), do: false

  @doc "The route patterns the tiles follow, each once, in tree order."
  @spec follows(t()) :: [String.t()]
  def follows(layout) do
    layout |> leaves() |> Enum.map(& &1.follow) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  @doc """
  Sets a split's ratio, the first child's share, clamped to `0.1..0.9`.
  """
  @spec resize(t(), String.t(), number()) :: t()
  def resize(%__MODULE__{root: nil} = layout, _id, _ratio), do: layout

  def resize(%__MODULE__{root: root} = layout, id, ratio) when is_number(ratio) do
    %{layout | root: map_node(root, id, &%{&1 | ratio: clamp_ratio(ratio)})}
  end

  @doc "Moves a split's divider one step towards `side`; the other axis is ignored."
  @spec nudge(t(), String.t(), side()) :: t()
  def nudge(%__MODULE__{root: nil} = layout, _id, _side), do: layout

  def nudge(%__MODULE__{root: root} = layout, id, side) do
    delta = if side in [:right, :down], do: @resize_step, else: -@resize_step
    axis = if side in [:left, :right], do: :h, else: :v

    case Enum.find(splits(root), &(&1.id == id and &1.direction == axis)) do
      nil -> layout
      split -> resize(layout, id, split.ratio + delta)
    end
  end

  defp splits(%{type: :leaf}), do: []
  defp splits(%{type: :split} = split), do: [split | splits(split.first) ++ splits(split.second)]

  @doc """
  Moves the divider nearest to the tile with `id` one step towards `side`.

  `:left` and `:right` move the closest side-by-side divider above the tile;
  `:up` and `:down` the closest top-and-bottom one. A tile with no divider on
  that axis is unchanged.
  """
  @spec resize_step(t(), String.t(), side()) :: t()
  def resize_step(%__MODULE__{root: nil} = layout, _id, _side), do: layout

  def resize_step(%__MODULE__{root: root} = layout, id, side) do
    axis = if side in [:left, :right], do: :h, else: :v
    delta = if side in [:right, :down], do: @resize_step, else: -@resize_step

    case ancestors(root, id) |> Enum.reverse() |> Enum.find(&(&1.direction == axis)) do
      nil -> layout
      split -> resize(layout, split.id, split.ratio + delta)
    end
  end

  @doc "Flips the direction of the split that holds the tile with `id`."
  @spec toggle_split(t(), String.t()) :: t()
  def toggle_split(%__MODULE__{root: nil} = layout, _id), do: layout

  def toggle_split(%__MODULE__{root: root} = layout, id) do
    case ancestors(root, id) |> List.last() do
      nil ->
        layout

      split ->
        flipped = if split.direction == :h, do: :v, else: :h
        %{layout | root: map_node(root, split.id, &%{&1 | direction: flipped})}
    end
  end

  @doc "Swaps the places of two tiles. Unknown or equal ids change nothing."
  @spec swap(t(), String.t(), String.t()) :: t()
  def swap(%__MODULE__{} = layout, id, id), do: layout
  def swap(%__MODULE__{root: nil} = layout, _a, _b), do: layout

  def swap(%__MODULE__{root: root} = layout, a, b) do
    with %{} = leaf_a <- fetch_leaf(layout, a),
         %{} = leaf_b <- fetch_leaf(layout, b) do
      %{layout | root: exchange(root, leaf_a, leaf_b)}
    else
      nil -> layout
    end
  end

  # One pass, because replacing `a` by `b` and then `b` by `a` would find the
  # copy just written and replace it back.
  defp exchange(%{type: :leaf, id: id}, %{id: id}, other), do: other
  defp exchange(%{type: :leaf, id: id}, other, %{id: id}), do: other
  defp exchange(%{type: :leaf} = leaf, _a, _b), do: leaf

  defp exchange(%{type: :split} = split, a, b) do
    %{split | first: exchange(split.first, a, b), second: exchange(split.second, a, b)}
  end

  @doc """
  The tile beside the tile with `id` on `side`, judged by the rectangles:
  the neighbour that shares the longest edge with it. `nil` at the edge of
  the workspace.
  """
  @spec neighbor(t(), String.t(), side()) :: String.t() | nil
  def neighbor(%__MODULE__{} = layout, id, side) do
    rects = leaf_rects(layout)

    case Map.fetch(rects, id) do
      :error ->
        nil

      {:ok, from} ->
        rects
        |> Enum.reject(fn {other, _} -> other == id end)
        |> Enum.filter(fn {_, rect} -> adjacent?(from, rect, side) end)
        |> Enum.max_by(fn {_, rect} -> overlap(from, rect, side) end, fn -> nil end)
        |> case do
          nil -> nil
          {other, _} -> other
        end
    end
  end

  defp adjacent?(from, rect, :left), do: close_to?(rect.x + rect.w, from.x)
  defp adjacent?(from, rect, :right), do: close_to?(rect.x, from.x + from.w)
  defp adjacent?(from, rect, :up), do: close_to?(rect.y + rect.h, from.y)
  defp adjacent?(from, rect, :down), do: close_to?(rect.y, from.y + from.h)

  defp close_to?(a, b), do: abs(a - b) < 1.0e-6

  defp overlap(from, rect, side) when side in [:left, :right] do
    max(0.0, min(from.y + from.h, rect.y + rect.h) - max(from.y, rect.y))
  end

  defp overlap(from, rect, _side) do
    max(0.0, min(from.x + from.w, rect.x + rect.w) - max(from.x, rect.x))
  end

  @doc "Swaps the tile with `id` and its neighbour on `side`; nothing at the edge."
  @spec move(t(), String.t(), side()) :: t()
  def move(%__MODULE__{} = layout, id, side) do
    case neighbor(layout, id, side) do
      nil -> layout
      other -> swap(layout, id, other)
    end
  end

  @doc """
  Where every tile and divider sits, as fractions of the workspace.

  `leaves` pairs each leaf with its rectangle in tree order; `handles` pairs
  each split with the whole rectangle it divides, so the host draws the
  divider at `ratio` along it and can turn a pointer position back into a
  ratio while dragging.
  """
  @spec rects(t()) :: %{
          leaves: [{leaf(), rect()}],
          handles: [{split(), rect()}]
        }
  def rects(%__MODULE__{root: nil}), do: %{leaves: [], handles: []}

  def rects(%__MODULE__{root: root}) do
    {leaves, handles} = walk_rects(root, %{x: 0.0, y: 0.0, w: 1.0, h: 1.0}, {[], []})
    %{leaves: Enum.reverse(leaves), handles: Enum.reverse(handles)}
  end

  defp walk_rects(%{type: :leaf} = leaf, rect, {leaves, handles}),
    do: {[{leaf, rect} | leaves], handles}

  defp walk_rects(%{type: :split} = split, rect, acc) do
    {first, second} = divide(rect, split.direction, split.ratio)
    {leaves, handles} = walk_rects(split.first, first, acc)
    walk_rects(split.second, second, {leaves, [{split, rect} | handles]})
  end

  defp divide(%{x: x, y: y, w: w, h: h}, :h, ratio) do
    cut = w * ratio
    {%{x: x, y: y, w: cut, h: h}, %{x: x + cut, y: y, w: w - cut, h: h}}
  end

  defp divide(%{x: x, y: y, w: w, h: h}, :v, ratio) do
    cut = h * ratio
    {%{x: x, y: y, w: w, h: cut}, %{x: x, y: y + cut, w: w, h: h - cut}}
  end

  defp leaf_rects(layout) do
    layout |> rects() |> Map.fetch!(:leaves) |> Map.new(fn {leaf, rect} -> {leaf.id, rect} end)
  end

  @doc """
  The URL form of the tree; `""` for an empty workspace.
  """
  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{root: nil}), do: ""
  def encode(%__MODULE__{root: root}), do: encode_node(root)

  defp encode_node(%{type: :leaf, path: path, follow: nil}), do: encode_leaf(path)

  defp encode_node(%{type: :leaf, path: path, follow: pattern}),
    do: encode_leaf(path) <> ">" <> encode_leaf(pattern)

  defp encode_node(%{type: :split} = split) do
    direction = if split.direction == :h, do: "h", else: "v"

    "#{direction}#{encode_ratio(split.ratio)}(#{encode_node(split.first)},#{encode_node(split.second)})"
  end

  defp encode_leaf(text) do
    URI.encode(text, &(&1 not in [?(, ?), ?,, ?>, ?%] and URI.char_unescaped?(&1)))
  end

  # `0.5` is written `.5`: the leading zero says nothing.
  defp encode_ratio(ratio) do
    ratio
    |> Float.round(3)
    |> :erlang.float_to_binary([:short])
    |> String.trim_leading("0")
  end

  @doc """
  Whether `path` names a page on this origin: one leading `/`, never `//host`,
  a scheme, a backslash a browser would read as `/`, or a space or control
  character a browser strips before it parses. Every tile path holds to it,
  so a tile can only ever show, or link to, a Bilimbi page.
  """
  @spec page_path?(term()) :: boolean()
  def page_path?("/" <> _ = path) do
    not String.starts_with?(path, "//") and not String.contains?(path, "\\") and
      not String.match?(path, ~r/[\x00-\x20\x7f]/) and
      match?(%URI{scheme: nil, host: nil, path: "/" <> _}, URI.parse(path))
  end

  def page_path?(_path), do: false

  @doc """
  Reads the URL form back into a tree with fresh ids. `""` is the empty
  workspace. Anything else that is not exactly the grammar is `:error`.
  """
  @spec decode(String.t()) :: {:ok, t()} | :error
  def decode(""), do: {:ok, empty()}

  def decode(encoded) when is_binary(encoded) do
    case parse_node(encoded, empty()) do
      {:ok, node, "", layout} -> {:ok, %{layout | root: node}}
      _ -> :error
    end
  end

  defp parse_node(<<direction, rest::binary>>, layout) when direction in [?h, ?v] do
    with {ratio, "(" <> rest} <- parse_ratio(rest),
         {:ok, first, "," <> rest, layout} <- parse_node(rest, layout),
         {:ok, second, ")" <> rest, layout} <- parse_node(rest, layout) do
      {id, layout} = next_id(layout, "s")

      {:ok,
       %{
         type: :split,
         id: id,
         direction: if(direction == ?h, do: :h, else: :v),
         ratio: clamp_ratio(ratio),
         first: first,
         second: second
       }, rest, layout}
    else
      _ -> :error
    end
  end

  defp parse_node(encoded, layout), do: parse_leaf(encoded, layout)

  defp parse_ratio("." <> rest) do
    case Float.parse("0." <> rest) do
      {ratio, rest} when ratio > 0.0 and ratio < 1.0 -> {ratio, rest}
      _ -> :error
    end
  end

  defp parse_ratio(_rest), do: :error

  defp parse_leaf(encoded, layout) do
    {raw, rest} = take_leaf(encoded, "")

    with [raw_path | raw_follow] when raw_path != "" and length(raw_follow) <= 1 <-
           String.split(raw, ">"),
         path when is_binary(path) <- safe_decode(raw_path),
         true <- page_path?(path),
         {:ok, follow} <- parse_follow(raw_follow) do
      {leaf, layout} = new_leaf(layout, path)
      {:ok, %{leaf | follow: follow}, rest, layout}
    else
      _ -> :error
    end
  end

  defp parse_follow([]), do: {:ok, nil}

  defp parse_follow([raw]) do
    with pattern when is_binary(pattern) <- safe_decode(raw),
         true <- follow_pattern?(pattern) do
      {:ok, pattern}
    else
      _ -> :error
    end
  end

  defp take_leaf(<<char, _::binary>> = rest, acc) when char in [?(, ?), ?,], do: {acc, rest}
  defp take_leaf(<<char, rest::binary>>, acc), do: take_leaf(rest, acc <> <<char>>)
  defp take_leaf("", acc), do: {acc, ""}

  defp safe_decode(raw) do
    URI.decode(raw)
  rescue
    ArgumentError -> :error
  end

  @doc """
  Carries `current`'s ids over to `incoming` where a leaf shows the same path,
  pairing in tree order, so a tree read back from the URL keeps the frames
  already on screen. Leaves with no match take fresh ids after `current`'s.
  """
  @spec reconcile(t(), t()) :: t()
  def reconcile(%__MODULE__{} = current, %__MODULE__{root: nil}),
    do: %{empty() | next_id: current.next_id}

  def reconcile(%__MODULE__{} = current, %__MODULE__{} = incoming) do
    {root, next, _spare} =
      relabel(incoming.root, current.next_id, leaves(current))

    %{incoming | root: root, next_id: next}
  end

  defp relabel(%{type: :leaf, path: path} = leaf, next, spare) do
    case Enum.split_with(spare, &(&1.path == path)) do
      {[match | rest_matches], others} ->
        {%{leaf | id: match.id}, next, rest_matches ++ others}

      {[], _} ->
        {%{leaf | id: "t#{next}"}, next + 1, spare}
    end
  end

  defp relabel(%{type: :split} = split, next, spare) do
    {first, next, spare} = relabel(split.first, next, spare)
    {second, next, spare} = relabel(split.second, next, spare)
    {%{split | id: "s#{next}", first: first, second: second}, next + 1, spare}
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp new_leaf(layout, path) do
    {id, layout} = next_id(layout, "t")
    {%{type: :leaf, id: id, path: path, follow: nil}, layout}
  end

  defp next_id(%__MODULE__{next_id: n} = layout, prefix),
    do: {"#{prefix}#{n}", %{layout | next_id: n + 1}}

  defp clamp_ratio(ratio), do: ratio |> max(@min_ratio) |> min(@max_ratio) |> Float.round(3)

  defp map_node(%{id: id} = node, id, fun), do: fun.(node)
  defp map_node(%{type: :leaf} = leaf, _id, _fun), do: leaf

  defp map_node(%{type: :split} = split, id, fun) do
    %{split | first: map_node(split.first, id, fun), second: map_node(split.second, id, fun)}
  end

  # The splits above the node with `id`, outermost first; `[]` when the node
  # is the root or absent.
  defp ancestors(%{id: id}, id), do: []
  defp ancestors(%{type: :leaf}, _id), do: []

  defp ancestors(%{type: :split} = split, id) do
    cond do
      contains?(split.first, id) -> [split | ancestors(split.first, id)]
      contains?(split.second, id) -> [split | ancestors(split.second, id)]
      true -> []
    end
  end

  defp contains?(%{id: id}, id), do: true
  defp contains?(%{type: :leaf}, _id), do: false

  defp contains?(%{type: :split} = split, id),
    do: contains?(split.first, id) or contains?(split.second, id)
end
