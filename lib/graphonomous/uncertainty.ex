defmodule Graphonomous.Uncertainty do
  @moduledoc """
  Uncertainty quantification for outcome-bearing nodes.

  Uses Wilson score intervals for confidence bounds.
  Only applies to nodes with evidence_count > 0.

  Nodes without evidence (e.g., file-ingested semantic nodes) return
  `:no_evidence` — they are either current or stale, not "uncertain"
  in the statistical sense.
  """

  alias Graphonomous.Store

  @type interval :: {lower :: float(), upper :: float()}

  @z 1.96

  @doc """
  Compute Wilson score confidence interval at 95% confidence.

  Returns `{lower, upper}` for nodes with evidence, or `:no_evidence`.
  """
  @spec interval(map()) :: interval() | :no_evidence
  def interval(%{evidence_count: 0}), do: :no_evidence
  def interval(%{evidence_count: nil}), do: :no_evidence

  def interval(%{confidence: c, evidence_count: n}) when is_number(n) and n > 0 do
    phat = clamp01(c)
    denom = 1.0 + @z * @z / n
    center = (phat + @z * @z / (2.0 * n)) / denom
    spread = @z * :math.sqrt((phat * (1.0 - phat) + @z * @z / (4.0 * n)) / n) / denom
    {max(0.0, center - spread), min(1.0, center + spread)}
  end

  def interval(_), do: :no_evidence

  @doc """
  Propagate uncertainty outward from a node through :derived_from and :supports edges.

  For each child: if parent interval is wider than child's, widen child's interval.
  Returns the count of widened child nodes.
  """
  @spec propagate(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def propagate(node_id) when is_binary(node_id) do
    with {:ok, parent_node} <- Store.get_node(node_id) do
      parent_interval = interval(parent_node)

      case parent_interval do
        :no_evidence ->
          {:ok, 0}

        {p_lo, p_hi} ->
          parent_width = p_hi - p_lo

          # Walk outward through :derived_from and :supports edges
          children = get_child_nodes(node_id)

          widened =
            Enum.count(children, fn child ->
              child_interval = interval(child)

              case child_interval do
                :no_evidence ->
                  false

                {c_lo, c_hi} ->
                  child_width = c_hi - c_lo
                  edge_weight = get_edge_weight(node_id, child.id)
                  propagated_width = parent_width * edge_weight

                  if propagated_width > child_width do
                    # Annotate in metadata (don't change confidence/evidence_count)
                    meta = if is_map(child.metadata), do: child.metadata, else: %{}

                    updated_meta =
                      Map.put(meta, "propagated_uncertainty", %{
                        "from" => node_id,
                        "parent_width" => parent_width,
                        "propagated_width" => propagated_width,
                        "at" => DateTime.to_iso8601(DateTime.utc_now())
                      })

                    Store.update_node(child.id, %{metadata: updated_meta})
                    true
                  else
                    false
                  end
              end
            end)

          {:ok, widened}
      end
    end
  end

  @doc """
  Return nodes where investigation would most reduce uncertainty.

  Sorted by information gain (widest intervals with highest access_count first).
  Only includes nodes with evidence_count > 0 and interval width > min_gap.
  """
  @spec frontier(keyword()) :: [map()]
  def frontier(opts \\ []) do
    min_gap = Keyword.get(opts, :min_gap, 0.3)
    limit = Keyword.get(opts, :limit, 10)

    case Store.list_nodes(%{}) do
      {:ok, nodes} when is_list(nodes) ->
        nodes
        |> Enum.filter(fn node ->
          ec = Map.get(node, :evidence_count, 0) || 0
          ec > 0
        end)
        |> Enum.map(fn node ->
          {lo, hi} = interval(node)
          width = hi - lo
          ig = information_gain(node)

          %{
            node_id: node.id,
            content: node.content,
            confidence: node.confidence,
            evidence_count: node.evidence_count,
            interval: {lo, hi},
            width: width,
            information_gain: ig,
            access_count: node.access_count
          }
        end)
        |> Enum.filter(fn item -> item.width > min_gap end)
        |> Enum.sort_by(fn item -> item.information_gain end, :desc)
        |> Enum.take(limit)

      _ ->
        []
    end
  end

  @doc """
  Entropy proxy for a node. Maximum (1.0) for no-evidence nodes,
  interval width for evidence-bearing nodes.
  """
  @spec entropy(map()) :: float()
  def entropy(%{evidence_count: 0}), do: 1.0
  def entropy(%{evidence_count: nil}), do: 1.0

  def entropy(node) do
    case interval(node) do
      :no_evidence -> 1.0
      {lo, hi} -> hi - lo
    end
  end

  @doc """
  Expected interval narrowing from one additional evidence point.
  """
  @spec information_gain(map()) :: float()
  def information_gain(node) do
    current = entropy(node)
    ec = Map.get(node, :evidence_count, 0) || 0

    projected = interval(%{node | evidence_count: ec + 1})

    case projected do
      :no_evidence -> 0.0
      {lo, hi} -> max(0.0, current - (hi - lo))
    end
  end

  # -- Private helpers -------------------------------------------------------

  defp get_child_nodes(parent_id) do
    case Store.list_edges_for_node(parent_id) do
      {:ok, edges} ->
        edges
        |> Enum.filter(fn edge ->
          edge.source_id == parent_id and
            edge.edge_type in [:derived_from, :supports]
        end)
        |> Enum.map(fn edge ->
          case Store.get_node(edge.target_id) do
            {:ok, node} -> node
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp get_edge_weight(source_id, target_id) do
    case Store.list_edges_for_node(source_id) do
      {:ok, edges} ->
        edge = Enum.find(edges, fn e -> e.source_id == source_id and e.target_id == target_id end)
        if edge, do: edge.weight || 0.5, else: 0.5

      _ ->
        0.5
    end
  end

  defp clamp01(v) when is_number(v) and v < 0.0, do: 0.0
  defp clamp01(v) when is_number(v) and v > 1.0, do: 1.0
  defp clamp01(v) when is_number(v), do: v * 1.0
  defp clamp01(_), do: 0.5
end
