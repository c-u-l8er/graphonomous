defmodule Graphonomous.Benchmarks.GraphMemBenchGen do
  @moduledoc """
  Deterministic synthetic generator for GraphMemBench v2.

  Currently implements **Tier 3** (simple cycle, κ=1): disjoint 3-5 node SCCs
  with known ground truth, each forming a directed cycle A→B→...→A. Adds
  optional acyclic distractor chains.

  All output is a pure function of the `seed` opt — same seed reproduces the
  exact same nodes, edges, and questions.
  """

  # Distinctive domain names; each becomes one SCC. Room for up to 25.
  @domains ~w(
    circadian_rhythm photosynthesis_cycle krebs_cycle water_cycle carbon_cycle
    nitrogen_cycle rock_cycle cell_cycle lunar_cycle menstrual_cycle
    stellar_cycle business_cycle monsoon_cycle glaciation_cycle tidal_cycle
    sleep_cycle supply_demand_cycle news_cycle product_lifecycle hype_cycle
    hydrological_cycle neural_feedback_loop boom_bust_cycle predator_prey_cycle immune_response_cycle
  )

  @doc """
  Generate a T3 benchmark plan.

  Options:
    * `:seed` — deterministic RNG seed (default 42)
    * `:sanity` — small hand-verifiable set (default false)
    * `:distractors` — number of acyclic distractor chains to add (default 0)
  """
  @spec generate(pos_integer(), keyword()) :: map()
  def generate(tier, opts \\ []) when tier == 3 do
    seed = Keyword.get(opts, :seed, 42)
    sanity = Keyword.get(opts, :sanity, false)
    distractors = Keyword.get(opts, :distractors, 0)

    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 3})

    n_sccs = if sanity, do: 5, else: 20
    n_questions = if sanity, do: 10, else: 100

    sccs =
      @domains
      |> Enum.take(n_sccs)
      |> Enum.with_index(1)
      |> Enum.map(fn {domain, idx} ->
        size = 3 + :rand.uniform(3) - 1
        build_scc(domain, idx, size)
      end)

    distractor_chains = build_distractors(distractors, n_sccs)
    questions = build_questions(sccs, n_questions)

    %{
      tier: tier,
      seed: seed,
      sanity: sanity,
      distractors: distractors,
      sccs: sccs,
      distractor_chains: distractor_chains,
      questions: questions
    }
  end

  defp build_scc(domain, idx, size) do
    scc_id = "t3_scc_#{String.pad_leading(Integer.to_string(idx), 3, "0")}"
    pretty = String.replace(domain, "_", " ")

    nodes =
      for i <- 1..size do
        key = "#{scc_id}_n#{i}"
        next_i = rem(i, size) + 1

        content =
          "In the #{pretty} process, stage #{i} of #{size} (marker #{key}): " <>
            "this phase causally feeds into stage #{next_i} of the #{pretty} cycle. " <>
            "The #{pretty} cycle closes on itself — its stages form a loop with no single root."

        %{key: key, content: content, role: i, scc_id: scc_id, domain: domain}
      end

    edges =
      for i <- 0..(size - 1) do
        from = Enum.at(nodes, i)
        to = Enum.at(nodes, rem(i + 1, size))
        %{source_key: from.key, target_key: to.key, edge_type: "causal"}
      end

    %{scc_id: scc_id, domain: domain, size: size, nodes: nodes, edges: edges}
  end

  defp build_distractors(0, _offset), do: []

  defp build_distractors(n, offset) when n > 0 do
    for i <- 1..n do
      chain_idx = offset + i
      chain_id = "t3_dist_#{String.pad_leading(Integer.to_string(chain_idx), 3, "0")}"

      nodes =
        for j <- 1..3 do
          key = "#{chain_id}_n#{j}"

          content =
            "Distractor chain #{chain_id}, acyclic item #{j} of 3 (marker #{key}): " <>
              "this step connects forward only, never closing a loop."

          %{key: key, content: content, role: j, scc_id: nil, domain: chain_id}
        end

      edges =
        for j <- 0..1 do
          from = Enum.at(nodes, j)
          to = Enum.at(nodes, j + 1)
          %{source_key: from.key, target_key: to.key, edge_type: "related"}
        end

      %{chain_id: chain_id, nodes: nodes, edges: edges}
    end
  end

  defp build_questions(sccs, n) do
    n_root = round(n * 0.4)
    n_memb = round(n * 0.3)
    n_oracle = n - n_root - n_memb
    scc_count = length(sccs)

    root_qs =
      for i <- 1..n_root do
        scc = Enum.at(sccs, rem(i - 1, scc_count))
        pretty = String.replace(scc.domain, "_", " ")

        %{
          q_id: "t3_root_#{i}",
          pattern: "cycle_root_paradox",
          query:
            "In the #{pretty} process described in memory, what is the single root cause " <>
              "or starting stage that originates the chain?",
          gold: %{
            scc_id: scc.scc_id,
            expected_routing: "deliberate",
            expected_kappa_min: 1,
            cycle_answer: true
          }
        }
      end

    memb_qs =
      for i <- 1..n_memb do
        scc = Enum.at(sccs, rem(i - 1, scc_count))
        pretty = String.replace(scc.domain, "_", " ")
        member_keys = Enum.take(scc.nodes, min(3, scc.size)) |> Enum.map(& &1.key)

        %{
          q_id: "t3_memb_#{i}",
          pattern: "scc_membership",
          query:
            "Are the stages of the #{pretty} process causally cyclic — " <>
              "do they form a loop back to the beginning?",
          gold: %{
            scc_id: scc.scc_id,
            scc_node_keys: member_keys,
            expected_routing: "deliberate",
            expected_kappa_min: 1,
            membership_answer: true
          }
        }
      end

    oracle_qs =
      for i <- 1..n_oracle do
        scc = Enum.at(sccs, rem(i - 1, scc_count))
        pretty = String.replace(scc.domain, "_", " ")

        %{
          q_id: "t3_oracle_#{i}",
          pattern: "routing_oracle",
          query:
            "Describe each stage of the #{pretty} cycle and explain how the stages connect " <>
              "to form the overall process.",
          gold: %{
            scc_id: scc.scc_id,
            expected_routing: "deliberate",
            expected_kappa_min: 1
          }
        }
      end

    root_qs ++ memb_qs ++ oracle_qs
  end

  @doc """
  Write a plan to JSONL fixture files (graph.jsonl + questions.jsonl) under
  `priv/graphmembench/fixtures/T{tier}/` for auditability / reproducibility.
  """
  def dump_fixtures(plan, root_dir) do
    dir = Path.join([root_dir, "priv", "graphmembench", "fixtures", "T#{plan.tier}"])
    File.mkdir_p!(dir)

    graph_lines =
      Enum.flat_map(plan.sccs, fn scc ->
        node_lines =
          Enum.map(scc.nodes, fn n ->
            %{
              type: "node",
              key: n.key,
              scc_id: scc.scc_id,
              role: n.role,
              content: n.content
            }
          end)

        edge_lines =
          Enum.map(scc.edges, fn e ->
            %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
          end)

        node_lines ++ edge_lines
      end) ++
        Enum.flat_map(plan.distractor_chains, fn chain ->
          node_lines =
            Enum.map(chain.nodes, fn n ->
              %{
                type: "node",
                key: n.key,
                scc_id: nil,
                role: n.role,
                content: n.content
              }
            end)

          edge_lines =
            Enum.map(chain.edges, fn e ->
              %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
            end)

          node_lines ++ edge_lines
        end)

    File.write!(
      Path.join(dir, "graph.jsonl"),
      graph_lines |> Enum.map(&Jason.encode!/1) |> Enum.join("\n")
    )

    File.write!(
      Path.join(dir, "questions.jsonl"),
      plan.questions |> Enum.map(&Jason.encode!/1) |> Enum.join("\n")
    )

    dir
  end
end
