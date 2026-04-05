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

  # T5 contradiction subjects (paired with state transitions below).
  @t5_subjects [
    "project codename Ardent",
    "deployment pipeline Orion",
    "feature flag eta-beam",
    "service mesh handle Spectre",
    "database cluster Delphi",
    "ML model ingest_v3",
    "agent persona Nimbus",
    "telemetry pipeline Quartz",
    "build system Granite",
    "tenant config for account Vortex",
    "migration job Atlas-9",
    "cache layer Meridian",
    "search index Terra",
    "auth flow Sentinel",
    "data lake Horizon",
    "edge runtime Cirrus",
    "queue topic Nautilus",
    "feature store Lagoon",
    "scheduler Polaris",
    "observability stream Helix"
  ]

  @t5_state_pairs [
    {"phase alpha", "phase beta"},
    {"disabled", "enabled"},
    {"experimental", "generally available"},
    {"paused", "running"},
    {"single-region", "multi-region"},
    {"read-only mode", "read-write mode"},
    {"v1 schema", "v2 schema"},
    {"manual trigger", "automated trigger"},
    {"weekly cadence", "daily cadence"},
    {"on premises", "cloud hosted"},
    {"planning", "executing"},
    {"synchronous", "asynchronous"},
    {"opt-in", "default-on"},
    {"batch mode", "streaming mode"},
    {"deprecated", "reinstated"},
    {"internal only", "public-facing"},
    {"gated rollout", "full rollout"},
    {"replicated", "sharded"},
    {"snapshot-based", "log-based"},
    {"advisory-only", "enforcing"}
  ]

  @doc """
  Generate a T3 benchmark plan.

  Options:
    * `:seed` — deterministic RNG seed (default 42)
    * `:sanity` — small hand-verifiable set (default false)
    * `:distractors` — number of acyclic distractor chains to add (default 0)
  """
  @spec generate(pos_integer(), keyword()) :: map()
  def generate(tier, opts \\ [])

  # Tier 1 — Linear chains (κ=0 control)
  def generate(1, opts) do
    tier = 1
    seed = Keyword.get(opts, :seed, 42)
    sanity = Keyword.get(opts, :sanity, false)
    distractors = Keyword.get(opts, :distractors, 0)

    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 3})

    n_chains = if sanity, do: 5, else: 20
    n_questions = if sanity, do: 10, else: 100

    chains =
      @domains
      |> Enum.take(n_chains)
      |> Enum.with_index(1)
      |> Enum.map(fn {domain, idx} ->
        size = 3 + :rand.uniform(3) - 1
        build_linear_chain(domain, idx, size)
      end)

    distractor_chains = build_distractors(distractors, n_chains)
    questions = build_acyclic_questions(chains, n_questions, 1)

    %{
      tier: tier,
      seed: seed,
      sanity: sanity,
      distractors: distractors,
      chains: chains,
      distractor_chains: distractor_chains,
      questions: questions
    }
  end

  # Tier 2 — Branching DAG (κ=0 control)
  def generate(2, opts) do
    tier = 2
    seed = Keyword.get(opts, :seed, 42)
    sanity = Keyword.get(opts, :sanity, false)
    distractors = Keyword.get(opts, :distractors, 0)

    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 3})

    n_trees = if sanity, do: 5, else: 15
    n_questions = if sanity, do: 10, else: 100

    chains =
      @domains
      |> Enum.take(n_trees)
      |> Enum.with_index(1)
      |> Enum.map(fn {domain, idx} ->
        build_branching_tree(domain, idx)
      end)

    distractor_chains = build_distractors(distractors, n_trees)
    questions = build_acyclic_questions(chains, n_questions, 2)

    %{
      tier: tier,
      seed: seed,
      sanity: sanity,
      distractors: distractors,
      chains: chains,
      distractor_chains: distractor_chains,
      questions: questions
    }
  end

  def generate(3, opts) do
    tier = 3
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

  # Tier 4 — Multi-SCC with chord edges (κ≥2, fault-line spanning)
  def generate(4, opts) do
    tier = 4
    seed = Keyword.get(opts, :seed, 42)
    sanity = Keyword.get(opts, :sanity, false)
    distractors = Keyword.get(opts, :distractors, 0)

    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 3})

    n_sccs = if sanity, do: 5, else: 15
    n_questions = if sanity, do: 10, else: 100

    sccs =
      @domains
      |> Enum.take(n_sccs)
      |> Enum.with_index(1)
      |> Enum.map(fn {domain, idx} ->
        size = 4 + rem(idx, 3)
        build_dense_scc(domain, idx, size)
      end)

    distractor_chains = build_distractors(distractors, n_sccs)
    questions = build_t4_questions(sccs, n_questions)

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

  # Tier 5 — Adversarial contradiction (κ=0-1 mix, belief revision)
  def generate(5, opts) do
    tier = 5
    seed = Keyword.get(opts, :seed, 42)
    sanity = Keyword.get(opts, :sanity, false)
    distractors = Keyword.get(opts, :distractors, 0)

    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 3})

    n_pairs = if sanity, do: 10, else: 20
    n_questions = if sanity, do: 10, else: 100

    # Half cyclic (κ=1, bidirectional contradicts), half acyclic (κ=0, one-way)
    pairs =
      for idx <- 1..n_pairs do
        cyclic? = rem(idx, 2) == 1
        turn_offset = :rand.uniform(10) + 1
        build_contradiction_pair(idx, cyclic?, turn_offset)
      end

    distractor_chains = build_distractors(distractors, n_pairs)
    questions = build_t5_questions(pairs, n_questions)

    %{
      tier: tier,
      seed: seed,
      sanity: sanity,
      distractors: distractors,
      contradiction_pairs: pairs,
      distractor_chains: distractor_chains,
      questions: questions
    }
  end

  defp build_contradiction_pair(idx, cyclic?, turn_offset) do
    pair_id = "t5_pair_#{String.pad_leading(Integer.to_string(idx), 3, "0")}"
    subject = Enum.at(@t5_subjects, rem(idx - 1, length(@t5_subjects)))
    {old_state, new_state} = Enum.at(@t5_state_pairs, rem(idx - 1, length(@t5_state_pairs)))

    old_key = "#{pair_id}_old"
    new_key = "#{pair_id}_new"

    old_content =
      "At an earlier turn, #{subject} was in state \"#{old_state}\" (fact #{old_key}). " <>
        "Historical observation about #{subject}."

    new_content =
      "At a later turn (turn +#{turn_offset} after the prior fact), #{subject} is now in state \"#{new_state}\" (fact #{new_key}). " <>
        "This is the current, superseding observation about #{subject}."

    nodes = [
      %{
        key: old_key,
        content: old_content,
        role: :old,
        pair_id: pair_id,
        subject: subject,
        confidence: 0.5
      },
      %{
        key: new_key,
        content: new_content,
        role: :new,
        pair_id: pair_id,
        subject: subject,
        confidence: 0.9
      }
    ]

    edges =
      if cyclic? do
        # Bidirectional contradicts → 2-node SCC κ=1
        [
          %{source_key: old_key, target_key: new_key, edge_type: "contradicts"},
          %{source_key: new_key, target_key: old_key, edge_type: "contradicts"}
        ]
      else
        # Unidirectional supersedes → κ=0 control
        [%{source_key: new_key, target_key: old_key, edge_type: "supersedes"}]
      end

    %{
      pair_id: pair_id,
      subject: subject,
      cyclic?: cyclic?,
      turn_offset: turn_offset,
      old_state: old_state,
      new_state: new_state,
      nodes: nodes,
      edges: edges
    }
  end

  defp build_t5_questions(pairs, n) do
    n_resolution = round(n * 0.5)
    n_memb = round(n * 0.25)
    n_oracle = n - n_resolution - n_memb
    pair_count = length(pairs)

    resolution_qs =
      for i <- 1..n_resolution do
        pair = Enum.at(pairs, rem(i - 1, pair_count))

        %{
          q_id: "t5_res_#{i}",
          pattern: "contradiction_resolution",
          query:
            "What is the current state of #{pair.subject}? " <>
              "Give the latest superseding fact, not the outdated one.",
          gold: %{
            pair_id: pair.pair_id,
            expected_top1_key: "#{pair.pair_id}_new",
            cyclic?: pair.cyclic?,
            turn_offset: pair.turn_offset,
            expected_routing: if(pair.cyclic?, do: "deliberate", else: "fast"),
            expected_kappa_min: if(pair.cyclic?, do: 1, else: 0)
          }
        }
      end

    memb_qs =
      for i <- 1..n_memb do
        pair = Enum.at(pairs, rem(i - 1, pair_count))

        %{
          q_id: "t5_memb_#{i}",
          pattern: "scc_membership",
          query:
            "Are the two observations about #{pair.subject} stored in memory " <>
              "contradictory — do they form a cyclic contradiction?",
          gold: %{
            pair_id: pair.pair_id,
            cyclic?: pair.cyclic?,
            expected_routing: if(pair.cyclic?, do: "deliberate", else: "fast"),
            expected_kappa_min: if(pair.cyclic?, do: 1, else: 0),
            membership_answer: pair.cyclic?
          }
        }
      end

    oracle_qs =
      for i <- 1..n_oracle do
        pair = Enum.at(pairs, rem(i - 1, pair_count))

        %{
          q_id: "t5_oracle_#{i}",
          pattern: "routing_oracle",
          query: "Summarize what is known about #{pair.subject} across all observations.",
          gold: %{
            pair_id: pair.pair_id,
            cyclic?: pair.cyclic?,
            expected_routing: if(pair.cyclic?, do: "deliberate", else: "fast"),
            expected_kappa_min: if(pair.cyclic?, do: 1, else: 0)
          }
        }
      end

    resolution_qs ++ memb_qs ++ oracle_qs
  end

  defp build_linear_chain(domain, idx, size) do
    chain_id = "t1_chain_#{String.pad_leading(Integer.to_string(idx), 3, "0")}"
    pretty = String.replace(domain, "_", " ")

    nodes =
      for i <- 1..size do
        key = "#{chain_id}_n#{i}"

        content =
          "In the linear #{pretty} sequence, step #{i} of #{size} (marker #{key}): " <>
            "this step flows forward only, never looping back. The #{pretty} sequence " <>
            "has a clear starting point and a clear ending point."

        %{key: key, content: content, role: i, scc_id: nil, domain: domain, chain_id: chain_id}
      end

    edges =
      for i <- 0..(size - 2) do
        from = Enum.at(nodes, i)
        to = Enum.at(nodes, i + 1)
        %{source_key: from.key, target_key: to.key, edge_type: "causal"}
      end

    %{chain_id: chain_id, domain: domain, size: size, nodes: nodes, edges: edges}
  end

  defp build_branching_tree(domain, idx) do
    tree_id = "t2_tree_#{String.pad_leading(Integer.to_string(idx), 3, "0")}"
    pretty = String.replace(domain, "_", " ")

    # Small binary branching DAG: root -> {A, B}; A -> {A1, A2}; B -> {B1}.
    labels = ["root", "A", "B", "A1", "A2", "B1"]

    nodes =
      labels
      |> Enum.with_index(1)
      |> Enum.map(fn {label, role} ->
        key = "#{tree_id}_#{label}"

        content =
          "In the branching #{pretty} decomposition, node #{label} (marker #{key}) is a " <>
            "non-cyclic junction — causality flows outward along the tree, never back to the root."

        %{key: key, content: content, role: role, scc_id: nil, domain: domain, chain_id: tree_id}
      end)

    index = Enum.into(Enum.with_index(nodes, 0), %{}, fn {n, i} -> {Enum.at(labels, i), n} end)

    edges =
      [
        {"root", "A"},
        {"root", "B"},
        {"A", "A1"},
        {"A", "A2"},
        {"B", "B1"}
      ]
      |> Enum.map(fn {from_l, to_l} ->
        from = index[from_l]
        to = index[to_l]
        %{source_key: from.key, target_key: to.key, edge_type: "causal"}
      end)

    %{chain_id: tree_id, domain: domain, size: length(nodes), nodes: nodes, edges: edges}
  end

  defp build_acyclic_questions(chains, n, tier) do
    n_rank = round(n * 0.5)
    n_memb = round(n * 0.25)
    n_oracle = n - n_rank - n_memb
    chain_count = length(chains)
    prefix = "t#{tier}"

    rank_qs =
      for i <- 1..n_rank do
        chain = Enum.at(chains, rem(i - 1, chain_count))
        pretty = String.replace(chain.domain, "_", " ")

        %{
          q_id: "#{prefix}_rank_#{i}",
          pattern: "linear_recall",
          query: "What are the steps of the #{pretty} sequence, in order from start to end?",
          gold: %{
            scc_id: chain.chain_id,
            expected_routing: "fast",
            expected_kappa_min: 0
          }
        }
      end

    memb_qs =
      for i <- 1..n_memb do
        chain = Enum.at(chains, rem(i - 1, chain_count))
        pretty = String.replace(chain.domain, "_", " ")

        %{
          q_id: "#{prefix}_memb_#{i}",
          pattern: "scc_membership",
          query:
            "Are the steps of the #{pretty} sequence causally cyclic — " <>
              "do they loop back to the beginning?",
          gold: %{
            scc_id: chain.chain_id,
            expected_routing: "fast",
            expected_kappa_min: 0,
            membership_answer: false
          }
        }
      end

    oracle_qs =
      for i <- 1..n_oracle do
        chain = Enum.at(chains, rem(i - 1, chain_count))
        pretty = String.replace(chain.domain, "_", " ")

        %{
          q_id: "#{prefix}_oracle_#{i}",
          pattern: "routing_oracle",
          query: "Describe the #{pretty} sequence and how its steps connect.",
          gold: %{
            scc_id: chain.chain_id,
            expected_routing: "fast",
            expected_kappa_min: 0
          }
        }
      end

    rank_qs ++ memb_qs ++ oracle_qs
  end

  defp build_dense_scc(domain, idx, size) do
    scc_id = "t4_scc_#{String.pad_leading(Integer.to_string(idx), 3, "0")}"
    pretty = String.replace(domain, "_", " ")

    nodes =
      for i <- 1..size do
        key = "#{scc_id}_n#{i}"

        content =
          "In the densely connected #{pretty} process, stage #{i} of #{size} " <>
            "(marker #{key}): this stage is part of a multi-cycle structure " <>
            "with several redundant feedback paths — it is not a simple root."

        %{key: key, content: content, role: i, scc_id: scc_id, domain: domain}
      end

    # Bidirectional ring + diameter chords → dense SCC with κ≥2.
    half = div(size, 2)

    forward_edges =
      for i <- 0..(size - 1) do
        from = Enum.at(nodes, i)
        to = Enum.at(nodes, rem(i + 1, size))
        %{source_key: from.key, target_key: to.key, edge_type: "causal"}
      end

    backward_edges =
      for i <- 0..(size - 1) do
        from = Enum.at(nodes, rem(i + 1, size))
        to = Enum.at(nodes, i)
        %{source_key: from.key, target_key: to.key, edge_type: "feedback"}
      end

    chord_edges =
      for i <- 0..(size - 1), rem(i, 2) == 0 do
        from = Enum.at(nodes, i)
        to = Enum.at(nodes, rem(i + half, size))
        %{source_key: from.key, target_key: to.key, edge_type: "causal"}
      end

    edges = forward_edges ++ backward_edges ++ chord_edges

    # Compute observed κ locally — Topology.analyze is generic over strings.
    node_keys = Enum.map(nodes, & &1.key)

    edge_maps =
      Enum.map(edges, fn e -> %{source_id: e.source_key, target_id: e.target_key} end)

    adjacency = Graphonomous.Topology.build_adjacency(node_keys, edge_maps)
    analysis = Graphonomous.Topology.analyze(adjacency)
    observed_kappa = Map.get(analysis, :max_kappa, 0)

    fault_line_keys =
      analysis
      |> Map.get(:sccs, [])
      |> Enum.flat_map(fn scc ->
        scc
        |> Map.get(:fault_line_edges, [])
        |> Enum.flat_map(fn
          %{source: s, target: t} -> [s, t]
          _ -> []
        end)
      end)
      |> Enum.uniq()

    %{
      scc_id: scc_id,
      domain: domain,
      size: size,
      nodes: nodes,
      edges: edges,
      observed_kappa: observed_kappa,
      fault_line_keys: fault_line_keys
    }
  end

  defp build_t4_questions(sccs, n) do
    n_faultline = round(n * 0.5)
    n_memb = round(n * 0.25)
    n_oracle = n - n_faultline - n_memb
    scc_count = length(sccs)

    faultline_qs =
      for i <- 1..n_faultline do
        scc = Enum.at(sccs, rem(i - 1, scc_count))
        pretty = String.replace(scc.domain, "_", " ")

        %{
          q_id: "t4_fault_#{i}",
          pattern: "faultline_spanning",
          query:
            "In the #{pretty} process, which stages sit at the transition boundary " <>
              "between the sub-cycles and act as the main junctions?",
          gold: %{
            scc_id: scc.scc_id,
            fault_line_keys: scc.fault_line_keys,
            expected_routing: "deliberate",
            expected_kappa_min: max(scc.observed_kappa, 1)
          }
        }
      end

    memb_qs =
      for i <- 1..n_memb do
        scc = Enum.at(sccs, rem(i - 1, scc_count))
        pretty = String.replace(scc.domain, "_", " ")

        %{
          q_id: "t4_memb_#{i}",
          pattern: "scc_membership",
          query:
            "Are the stages of the densely connected #{pretty} process causally cyclic " <>
              "with multiple redundant feedback paths?",
          gold: %{
            scc_id: scc.scc_id,
            expected_routing: "deliberate",
            expected_kappa_min: max(scc.observed_kappa, 1),
            membership_answer: true
          }
        }
      end

    oracle_qs =
      for i <- 1..n_oracle do
        scc = Enum.at(sccs, rem(i - 1, scc_count))
        pretty = String.replace(scc.domain, "_", " ")

        %{
          q_id: "t4_oracle_#{i}",
          pattern: "routing_oracle",
          query:
            "Summarize the interconnected stages of the #{pretty} process and " <>
              "their multi-directional feedback loops.",
          gold: %{
            scc_id: scc.scc_id,
            expected_routing: "deliberate",
            expected_kappa_min: max(scc.observed_kappa, 1)
          }
        }
      end

    faultline_qs ++ memb_qs ++ oracle_qs
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
      case plan.tier do
        1 -> dump_acyclic_graph_lines(plan)
        2 -> dump_acyclic_graph_lines(plan)
        3 -> dump_t3_graph_lines(plan)
        4 -> dump_t4_graph_lines(plan)
        5 -> dump_t5_graph_lines(plan)
      end

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

  defp dump_t3_graph_lines(plan) do
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
  end

  defp dump_acyclic_graph_lines(plan) do
    Enum.flat_map(plan.chains, fn chain ->
      node_lines =
        Enum.map(chain.nodes, fn n ->
          %{type: "node", key: n.key, chain_id: chain.chain_id, role: n.role, content: n.content}
        end)

      edge_lines =
        Enum.map(chain.edges, fn e ->
          %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
        end)

      node_lines ++ edge_lines
    end) ++
      Enum.flat_map(plan.distractor_chains, fn chain ->
        node_lines =
          Enum.map(chain.nodes, fn n ->
            %{type: "node", key: n.key, scc_id: nil, role: n.role, content: n.content}
          end)

        edge_lines =
          Enum.map(chain.edges, fn e ->
            %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
          end)

        node_lines ++ edge_lines
      end)
  end

  defp dump_t4_graph_lines(plan) do
    Enum.flat_map(plan.sccs, fn scc ->
      node_lines =
        Enum.map(scc.nodes, fn n ->
          %{
            type: "node",
            key: n.key,
            scc_id: scc.scc_id,
            role: n.role,
            content: n.content,
            observed_kappa: scc.observed_kappa,
            fault_line: n.key in scc.fault_line_keys
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
            %{type: "node", key: n.key, scc_id: nil, role: n.role, content: n.content}
          end)

        edge_lines =
          Enum.map(chain.edges, fn e ->
            %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
          end)

        node_lines ++ edge_lines
      end)
  end

  defp dump_t5_graph_lines(plan) do
    Enum.flat_map(plan.contradiction_pairs, fn pair ->
      node_lines =
        Enum.map(pair.nodes, fn n ->
          %{
            type: "node",
            key: n.key,
            pair_id: pair.pair_id,
            role: n.role,
            cyclic: pair.cyclic?,
            turn_offset: pair.turn_offset,
            confidence: n.confidence,
            content: n.content
          }
        end)

      edge_lines =
        Enum.map(pair.edges, fn e ->
          %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
        end)

      node_lines ++ edge_lines
    end) ++
      Enum.flat_map(plan.distractor_chains, fn chain ->
        node_lines =
          Enum.map(chain.nodes, fn n ->
            %{type: "node", key: n.key, role: n.role, content: n.content}
          end)

        edge_lines =
          Enum.map(chain.edges, fn e ->
            %{type: "edge", source: e.source_key, target: e.target_key, edge_type: e.edge_type}
          end)

        node_lines ++ edge_lines
      end)
  end
end
