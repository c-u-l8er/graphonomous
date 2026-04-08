defmodule Graphonomous.EntityResolver do
  @moduledoc """
  Entity resolution pipeline for Graphonomous.

  Extracts entity mentions from text content, resolves them against known
  entities (fuzzy match on name + aliases), creates new entities for unresolved
  mentions, and links nodes to resolved entities via entity_node_links.

  This module is called as a post-store hook from Graph.store_node/1 and can
  also be invoked during retrieval to extract entities from queries.

  Phase 1 uses simple heuristic extraction (proper nouns, quoted terms, known
  patterns). LLM-driven NER is deferred to Phase 2.
  """

  alias Graphonomous.Store

  @type mention :: %{
          text: String.t(),
          entity_type: atom()
        }

  @type resolution :: %{
          entity_id: String.t(),
          entity_name: String.t(),
          match_type: :exact | :alias | :fuzzy,
          mention: mention()
        }

  # Minimum string length to consider as an entity mention
  @min_mention_length 2
  # Similarity threshold for fuzzy matching (Jaro-Winkler)
  @fuzzy_threshold 0.85

  # ── Extraction ──────────────────────────────────────────────────────

  @doc """
  Extract entity mentions from text content using heuristic patterns.

  Returns a list of `%{text: ..., entity_type: ...}` maps.
  """
  @spec extract_mentions(String.t()) :: [mention()]
  def extract_mentions(text) when is_binary(text) do
    (extract_proper_nouns(text) ++
       extract_quoted_terms(text) ++
       extract_known_patterns(text))
    |> Enum.uniq_by(fn m -> String.downcase(m.text) end)
    |> Enum.reject(fn m -> String.length(m.text) < @min_mention_length end)
  end

  def extract_mentions(_), do: []

  # Proper nouns: capitalized words not at sentence start, multi-word capitalized phrases
  defp extract_proper_nouns(text) do
    # Multi-word proper noun phrases (2-4 consecutive capitalized words)
    multi_word =
      Regex.scan(~r/(?<![.!?\n]\s)(?<!\A)([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})/, text)
      |> Enum.map(fn [_, match] -> %{text: String.trim(match), entity_type: :other} end)

    # Single capitalized words not at sentence boundaries, min 3 chars
    # Exclude common English words that happen to be capitalized
    single_word =
      Regex.scan(~r/(?<![.!?\n]\s)(?<!\A)\b([A-Z][a-z]{2,})\b/, text)
      |> Enum.map(fn [_, match] -> match end)
      |> Enum.reject(&common_word?/1)
      |> Enum.map(fn word -> %{text: word, entity_type: :other} end)

    multi_word ++ single_word
  end

  # Quoted terms: "something" or 'something'
  defp extract_quoted_terms(text) do
    Regex.scan(~r/"([^"]{2,50})"/, text)
    |> Enum.map(fn [_, match] -> %{text: match, entity_type: :concept} end)
  end

  # Known entity patterns: @mentions, tool names, language names, etc.
  defp extract_known_patterns(text) do
    # Programming language / tool names (case-insensitive match but preserve original)
    tool_pattern =
      ~r/\b(Elixir|Phoenix|PostgreSQL|SQLite|Python|Rust|TypeScript|JavaScript|React|Node\.js|Docker|Kubernetes|GitHub|Supabase|Redis|Nginx|Linux|macOS|Windows|Claude|ChatGPT|Graphonomous|MCP)\b/

    Regex.scan(tool_pattern, text)
    |> Enum.map(fn [_, match] -> %{text: match, entity_type: :tool} end)
  end

  @common_words MapSet.new(~w(
    The This That These Those What Which Where When How Why Who
    Also However Furthermore Moreover Additionally Meanwhile
    Because Although Since While Until Before After During
    Each Every Some Many Much Most Several Few All Both
    Here There Then Now Just Still Already Yet
    Would Could Should Might Must Shall Will Can May
    Being Having Making Getting Going Coming Taking
    Very Really Actually Indeed Certainly Probably
    First Second Third Next Last Final
    Good Better Best Great Important
  ))

  defp common_word?(word), do: MapSet.member?(@common_words, word)

  # ── Resolution ──────────────────────────────────────────────────────

  @doc """
  Resolve a list of mentions against known entities.

  Returns `{resolved, unresolved}` where resolved is a list of resolution
  maps and unresolved is a list of mentions that didn't match.
  """
  @spec resolve([mention()]) :: {[resolution()], [mention()]}
  def resolve(mentions) when is_list(mentions) do
    all_entities = Store.list_entities()

    Enum.reduce(mentions, {[], []}, fn mention, {resolved, unresolved} ->
      case resolve_mention(mention, all_entities) do
        {:ok, resolution} -> {[resolution | resolved], unresolved}
        :unresolved -> {resolved, [mention | unresolved]}
      end
    end)
    |> then(fn {r, u} -> {Enum.reverse(r), Enum.reverse(u)} end)
  end

  defp resolve_mention(mention, all_entities) do
    canonical = String.downcase(String.trim(mention.text))

    # 1. Exact canonical name match
    case Enum.find(all_entities, fn e -> e.canonical_name == canonical end) do
      %{id: id, name: name} ->
        {:ok, %{entity_id: id, entity_name: name, match_type: :exact, mention: mention}}

      nil ->
        # 2. Alias match
        case Enum.find(all_entities, fn e ->
               Enum.any?(e.aliases, fn a -> String.downcase(a) == canonical end)
             end) do
          %{id: id, name: name} ->
            {:ok, %{entity_id: id, entity_name: name, match_type: :alias, mention: mention}}

          nil ->
            # 3. Fuzzy match (Jaro-Winkler)
            fuzzy_match(mention, canonical, all_entities)
        end
    end
  end

  defp fuzzy_match(mention, canonical, all_entities) do
    best =
      all_entities
      |> Enum.flat_map(fn entity ->
        names = [entity.canonical_name | Enum.map(entity.aliases, &String.downcase/1)]

        Enum.map(names, fn name ->
          {entity, jaro_winkler(canonical, name)}
        end)
      end)
      |> Enum.max_by(fn {_e, score} -> score end, fn -> {nil, 0.0} end)

    case best do
      {%{id: id, name: name}, score} when score >= @fuzzy_threshold ->
        {:ok, %{entity_id: id, entity_name: name, match_type: :fuzzy, mention: mention}}

      _ ->
        :unresolved
    end
  end

  # ── Create or Link ──────────────────────────────────────────────────

  @doc """
  Process entity mentions for a node: resolve known entities and create new
  ones for unresolved mentions, then create entity_node_links for all.

  Returns a list of `%{entity_id, entity_name, match_type, created}` maps.
  """
  @spec resolve_and_link(String.t(), String.t()) :: {:ok, [map()]}
  def resolve_and_link(node_id, content) when is_binary(node_id) and is_binary(content) do
    mentions = extract_mentions(content)
    {resolved, unresolved} = resolve(mentions)

    # Link resolved entities to the node
    resolved_results =
      Enum.map(resolved, fn r ->
        _ = Store.insert_entity_node_link(r.entity_id, node_id, "mentions")
        Map.put(r, :created, false)
      end)

    # Create new entities for unresolved mentions and link them
    created_results =
      Enum.map(unresolved, fn mention ->
        {:ok, entity} =
          Store.insert_entity(%{
            name: mention.text,
            entity_type: mention.entity_type,
            aliases: []
          })

        _ = Store.insert_entity_node_link(entity.id, node_id, "mentions")

        %{
          entity_id: entity.id,
          entity_name: entity.name,
          match_type: :new,
          mention: mention,
          created: true
        }
      end)

    {:ok, resolved_results ++ created_results}
  end

  # ── Query Entity Lookup ─────────────────────────────────────────────

  @doc """
  Extract entities from a query string and return matching entity IDs.

  Used by the Retriever to add an entity-lookup path alongside ANN+BM25.
  """
  @spec query_entities(String.t()) :: [%{entity_id: String.t(), node_ids: [String.t()]}]
  def query_entities(query) when is_binary(query) do
    mentions = extract_mentions(query)
    {resolved, _unresolved} = resolve(mentions)

    Enum.map(resolved, fn r ->
      node_ids = Store.node_ids_for_entity(r.entity_id)
      %{entity_id: r.entity_id, entity_name: r.entity_name, node_ids: node_ids}
    end)
  end

  # ── Jaro-Winkler similarity ────────────────────────────────────────

  @doc false
  def jaro_winkler(s1, s2) when is_binary(s1) and is_binary(s2) do
    jaro = String.jaro_distance(s1, s2)
    # Winkler prefix bonus
    prefix_len = common_prefix_length(s1, s2, 4)
    p = 0.1
    jaro + prefix_len * p * (1.0 - jaro)
  end

  defp common_prefix_length(s1, s2, max) do
    s1_chars = String.graphemes(s1)
    s2_chars = String.graphemes(s2)

    s1_chars
    |> Enum.zip(s2_chars)
    |> Enum.take(max)
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> length()
  end
end
