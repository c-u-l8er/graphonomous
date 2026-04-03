defmodule Graphonomous.EdgeExtractor do
  @moduledoc """
  Extracts inter-file reference edges from node content.

  Scans file content for import statements, module references, and file path
  references to create edges between related nodes in the knowledge graph.
  Supports Elixir, JavaScript/TypeScript, and Markdown cross-references.
  """

  require Logger

  alias Graphonomous.Graph

  @backref_similarity_threshold 0.75

  @type edge_candidate :: %{
          source_id: String.t(),
          target_pattern: String.t(),
          edge_type: atom(),
          weight: float()
        }

  @doc """
  Extract edge candidates from a list of nodes.

  Returns a list of `{source_id, target_id, edge_type, weight}` tuples
  for edges that should be created between existing nodes.
  """
  @spec extract_edges([map()]) :: [{String.t(), String.t(), atom(), float()}]
  def extract_edges(nodes) when is_list(nodes) do
    # Build lookup indices
    path_index = build_path_index(nodes)
    module_index = build_module_index(nodes)

    nodes
    |> Enum.flat_map(fn node ->
      content = Map.get(node, :content, "")
      meta = Map.get(node, :metadata, %{})
      path = Map.get(meta, "relative_path", "") |> to_string()
      ext = Map.get(meta, "extension", "") |> to_string()

      candidates = extract_references(content, path, ext)

      Enum.flat_map(candidates, fn %{target_pattern: pattern, edge_type: type, weight: weight} ->
        resolve_targets(pattern, path_index, module_index)
        |> Enum.map(fn target_id -> {node.id, target_id, type, weight} end)
      end)
    end)
    |> Enum.uniq()
    |> Enum.reject(fn {src, tgt, _, _} -> src == tgt end)
  end

  @doc """
  Create extracted edges in the knowledge graph.
  Returns the count of edges created.
  """
  @spec create_extracted_edges([map()]) :: non_neg_integer()
  def create_extracted_edges(nodes) do
    forward_edges = extract_edges(nodes)

    forward_count =
      Enum.reduce(forward_edges, 0, fn {src_id, tgt_id, edge_type, weight}, count ->
        case Graphonomous.link_nodes(src_id, tgt_id, %{
               edge_type: Atom.to_string(edge_type),
               weight: weight,
               metadata: %{"source" => "edge_extractor", "automated" => true}
             }) do
          {:error, _} -> count
          _ -> count + 1
        end
      end)

    # After forward edges, compute semantic back-references to create cycles
    backref_count = extract_semantic_backrefs(forward_edges)

    forward_count + backref_count
  end

  @doc """
  After forward edge creation, compute cosine similarity between
  target and source embeddings. If similarity > threshold, create a
  reverse `:supports` edge. This enables cycle formation (κ > 0).
  """
  @spec extract_semantic_backrefs([{String.t(), String.t(), atom(), float()}]) ::
          non_neg_integer()
  def extract_semantic_backrefs(forward_edges) when is_list(forward_edges) do
    forward_edges
    |> Enum.uniq_by(fn {src, tgt, _, _} -> {src, tgt} end)
    |> Enum.reduce(0, fn {src_id, tgt_id, _type, _weight}, count ->
      with {:ok, src_node} <- Graph.get_node(src_id),
           {:ok, tgt_node} <- Graph.get_node(tgt_id) do
        src_vec = Graph.decode_embedding_blob(src_node.embedding)
        tgt_vec = Graph.decode_embedding_blob(tgt_node.embedding)

        similarity = Graph.cosine_similarity(tgt_vec, src_vec)

        if similarity >= @backref_similarity_threshold do
          case Graphonomous.link_nodes(tgt_id, src_id, %{
                 edge_type: "supports",
                 weight: Float.round(similarity * 0.6, 3),
                 metadata: %{
                   "source" => "edge_extractor_backref",
                   "automated" => true,
                   "similarity" => Float.round(similarity, 4)
                 }
               }) do
            {:error, _} -> count
            _ -> count + 1
          end
        else
          count
        end
      else
        _ -> count
      end
    end)
  end

  ## Reference extraction by file type

  defp extract_references(content, _path, ext) when ext in [".ex", ".exs"] do
    extract_elixir_refs(content)
  end

  defp extract_references(content, _path, ext) when ext in [".js", ".ts", ".tsx", ".jsx"] do
    extract_js_refs(content)
  end

  defp extract_references(content, _path, ".md") do
    extract_markdown_refs(content)
  end

  defp extract_references(_content, _path, _ext), do: []

  ## Elixir references

  defp extract_elixir_refs(content) do
    alias_refs =
      Regex.scan(~r/(?:alias|import|use|require)\s+([\w.]+)/, content)
      |> Enum.map(fn [_, module] ->
        %{target_pattern: {:module, module}, edge_type: :derived_from, weight: 0.7}
      end)

    # Detect module references like Graphonomous.Store
    module_refs =
      Regex.scan(~r/\b(Graphonomous\.[\w.]+)\b/, content)
      |> Enum.map(fn [_, module] ->
        %{target_pattern: {:module, module}, edge_type: :related, weight: 0.5}
      end)

    (alias_refs ++ module_refs)
    |> Enum.uniq_by(& &1.target_pattern)
  end

  ## JavaScript/TypeScript references

  defp extract_js_refs(content) do
    # import/require statements
    import_refs =
      Regex.scan(
        ~r/(?:import\s+.*?from\s+['"]([^'"]+)['"]|require\s*\(\s*['"]([^'"]+)['"]\s*\))/,
        content
      )
      |> Enum.map(fn
        [_, path, ""] -> path
        [_, "", path] -> path
        [_, path] -> path
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&String.starts_with?(&1, "@"))
      |> Enum.map(fn path ->
        %{target_pattern: {:path_ref, path}, edge_type: :derived_from, weight: 0.7}
      end)

    import_refs
  end

  ## Markdown references

  defp extract_markdown_refs(content) do
    # File path references like `graphonomous/lib/...` or links
    path_refs =
      Regex.scan(~r/`([a-zA-Z][\w.\-\/]+\.(?:ex|exs|ts|js|md|json))`/, content)
      |> Enum.map(fn [_, path] ->
        %{target_pattern: {:path_ref, path}, edge_type: :related, weight: 0.6}
      end)

    # Cross-project references like "Graphonomous", "BendScript", etc.
    project_refs =
      Regex.scan(
        ~r/\b(Graphonomous|BendScript|WebHost|Delegatic|FleetPrompt|Agentelic|AgenTroMatic|OpenSentience|SpecPrompt|GeoFleetic|TickTickClock)\b/,
        content
      )
      |> Enum.map(fn [_, name] ->
        domain = project_name_to_domain(name)
        %{target_pattern: {:domain, domain}, edge_type: :related, weight: 0.4}
      end)
      |> Enum.uniq_by(& &1.target_pattern)

    path_refs ++ project_refs
  end

  ## Index building

  defp build_path_index(nodes) do
    nodes
    |> Enum.reduce(%{}, fn node, acc ->
      meta = Map.get(node, :metadata, %{})
      rel_path = Map.get(meta, "relative_path", "") |> to_string()

      if rel_path != "" do
        # Index by full relative path and by basename
        basename = Path.basename(rel_path)

        acc
        |> Map.put(rel_path, node.id)
        |> Map.update(basename, [node.id], &[node.id | &1])
      else
        acc
      end
    end)
  end

  defp build_module_index(nodes) do
    nodes
    |> Enum.reduce(%{}, fn node, acc ->
      meta = Map.get(node, :metadata, %{})
      ext = Map.get(meta, "extension", "") |> to_string()

      if ext in [".ex", ".exs"] do
        content = Map.get(node, :content, "")

        case Regex.run(~r/defmodule\s+([\w.]+)\s+do/, content) do
          [_, module_name] -> Map.put(acc, module_name, node.id)
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  ## Target resolution

  defp resolve_targets({:module, module}, _path_index, module_index) do
    case Map.get(module_index, module) do
      nil -> []
      id -> [id]
    end
  end

  defp resolve_targets({:path_ref, ref_path}, path_index, _module_index) do
    # Try exact match first, then basename match
    case Map.get(path_index, ref_path) do
      id when is_binary(id) ->
        [id]

      _ ->
        basename = Path.basename(ref_path)

        case Map.get(path_index, basename) do
          ids when is_list(ids) -> Enum.take(ids, 1)
          _ -> []
        end
    end
  end

  defp resolve_targets({:domain, domain}, path_index, _module_index) do
    # Find any node in the target domain
    path_index
    |> Enum.find(fn {path, _id} ->
      is_binary(path) and String.starts_with?(path, domain)
    end)
    |> case do
      {_, id} when is_binary(id) -> [id]
      _ -> []
    end
  end

  ## Helpers

  defp project_name_to_domain(name) do
    case name do
      "Graphonomous" -> "graphonomous/"
      "BendScript" -> "bendscript.com/"
      "WebHost" -> "WebHost.Systems/"
      "Delegatic" -> "delegatic.com/"
      "FleetPrompt" -> "fleetprompt.com/"
      "Agentelic" -> "agentelic.com/"
      "AgenTroMatic" -> "agentromatic.com/"
      "OpenSentience" -> "opensentience.org/"
      "SpecPrompt" -> "specprompt.com/"
      "GeoFleetic" -> "geofleetic.com/"
      "TickTickClock" -> "ticktickclock.com/"
      _ -> name
    end
  end
end
