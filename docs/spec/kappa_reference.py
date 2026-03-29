#!/usr/bin/env python3
"""
κ Reference Implementation — Graph Intelligence Primitives

This module provides:
  1. SCC decomposition (Tarjan's algorithm)
  2. κ computation (minimum bidirectional cut across bipartitions of SCCs)
  3. Graph topology analysis (SCC map, routing decisions, fault line identification)
  4. Exhaustive proof verification (1,926,351 objects, zero counterexamples)

The κ invariant is the routing primitive for the [&] agent architecture:
  - κ = 0 → DAG region → single-pass retrieval (fast path)
  - κ > 0 → SCC region → iterative deliberation (Deliberatic)
  - κ value → deliberation budget (higher κ = more feedback loops = more iterations)

Port targets: Elixir (Graphonomous/Deliberatic), JavaScript (BendScript canvas).

PROVED RESULTS (algebraic + exhaustive computation):
  For finite directed graphs: κ(G) > 0 ⟺ Φ(G) > 0 ⟺ β₁(G) > 0
  For finite dynamical systems: κ(f) > 0 ⟺ f has periodic orbit (period > 1)
  Functor property: TransitionGraph preserves κ exactly
"""

import json
import time
from itertools import product as cart_product
from collections import defaultdict
from typing import Dict, List, Tuple, Optional, Set, Any


# ═══════════════════════════════════════════════════════════════
# PART 1: CORE GRAPH PRIMITIVES
# ═══════════════════════════════════════════════════════════════

class DirectedGraph:
    """A directed graph represented as an adjacency dict.
    
    Designed for knowledge graph subgraphs where nodes are string IDs
    and edges are typed relationships.
    """
    
    def __init__(self):
        self.nodes: Set[str] = set()
        self.edges: Dict[str, Set[str]] = defaultdict(set)  # src -> {dst, ...}
        self.edge_metadata: Dict[Tuple[str, str], dict] = {}  # (src, dst) -> metadata
    
    def add_node(self, node_id: str):
        self.nodes.add(node_id)
    
    def add_edge(self, src: str, dst: str, metadata: dict = None):
        self.nodes.add(src)
        self.nodes.add(dst)
        self.edges[src].add(dst)
        if metadata:
            self.edge_metadata[(src, dst)] = metadata
    
    def remove_edge(self, src: str, dst: str):
        self.edges[src].discard(dst)
        self.edge_metadata.pop((src, dst), None)
    
    def successors(self, node: str) -> Set[str]:
        return self.edges.get(node, set())
    
    def to_adj_matrix(self) -> Tuple[list, list]:
        """Convert to adjacency matrix for κ computation.
        Returns (node_list, adj_matrix)."""
        node_list = sorted(self.nodes)
        idx = {n: i for i, n in enumerate(node_list)}
        n = len(node_list)
        adj = [[0]*n for _ in range(n)]
        for src, dsts in self.edges.items():
            for dst in dsts:
                if src != dst:  # no self-loops for κ
                    adj[idx[src]][idx[dst]] = 1
        return node_list, adj


# ═══════════════════════════════════════════════════════════════
# PART 2: SCC DECOMPOSITION (Tarjan's Algorithm)
# ═══════════════════════════════════════════════════════════════

def tarjan_scc_matrix(adj: list, n: int) -> list:
    """Tarjan's SCC algorithm on adjacency matrix. Returns list of SCCs."""
    index_counter = [0]
    stack = []
    lowlink = [0] * n
    index = [0] * n
    on_stack = [False] * n
    initialized = [False] * n
    result = []

    def strongconnect(v):
        index[v] = index_counter[0]
        lowlink[v] = index_counter[0]
        index_counter[0] += 1
        initialized[v] = True
        stack.append(v)
        on_stack[v] = True

        for w in range(n):
            if adj[v][w]:
                if not initialized[w]:
                    strongconnect(w)
                    lowlink[v] = min(lowlink[v], lowlink[w])
                elif on_stack[w]:
                    lowlink[v] = min(lowlink[v], index[w])

        if lowlink[v] == index[v]:
            component = []
            while True:
                w = stack.pop()
                on_stack[w] = False
                component.append(w)
                if w == v:
                    break
            result.append(component)

    for v in range(n):
        if not initialized[v]:
            strongconnect(v)

    return result


def tarjan_scc_graph(graph: DirectedGraph) -> List[List[str]]:
    """Tarjan's SCC on a DirectedGraph. Returns list of SCCs as node ID lists."""
    node_list, adj = graph.to_adj_matrix()
    n = len(node_list)
    sccs = tarjan_scc_matrix(adj, n)
    return [[node_list[i] for i in scc] for scc in sccs]


# ═══════════════════════════════════════════════════════════════
# PART 3: κ COMPUTATION
# ═══════════════════════════════════════════════════════════════

def compute_kappa_matrix(adj: list, n: int, scc_nodes: list) -> dict:
    """Compute κ for a specific SCC given as a list of node indices.
    
    Returns:
        {
            'kappa': int,
            'min_cut_partition': (list, list),  # (A_indices, B_indices)
            'min_cut_edges_ab': int,
            'min_cut_edges_ba': int,
        }
    """
    scc_size = len(scc_nodes)
    if scc_size <= 1:
        return {'kappa': 0, 'min_cut_partition': None, 'min_cut_edges_ab': 0, 'min_cut_edges_ba': 0}
    
    min_kappa = float('inf')
    best_partition = None
    best_ab = 0
    best_ba = 0
    
    for mask in range(1, (1 << scc_size) - 1):
        A = [scc_nodes[i] for i in range(scc_size) if mask & (1 << i)]
        B = [scc_nodes[i] for i in range(scc_size) if not (mask & (1 << i))]
        if not A or not B:
            continue
        
        ab = sum(1 for a in A for b in B if adj[a][b])
        ba = sum(1 for b in B for a in A if adj[b][a])
        cut = min(ab, ba)
        
        if cut < min_kappa:
            min_kappa = cut
            best_partition = (A, B)
            best_ab = ab
            best_ba = ba
            if min_kappa == 0:
                break
    
    return {
        'kappa': min_kappa if min_kappa != float('inf') else 0,
        'min_cut_partition': best_partition,
        'min_cut_edges_ab': best_ab,
        'min_cut_edges_ba': best_ba,
    }


def compute_kappa_graph(graph: DirectedGraph, scc_node_ids: List[str]) -> dict:
    """Compute κ for an SCC specified by node IDs in a DirectedGraph.
    
    Returns:
        {
            'kappa': int,
            'scc_nodes': list of node IDs,
            'min_cut_partition': (list_A_ids, list_B_ids) or None,
            'fault_line_edges': list of (src, dst) edge tuples on the minimum cut,
        }
    """
    node_list, adj = graph.to_adj_matrix()
    idx = {n: i for i, n in enumerate(node_list)}
    scc_indices = [idx[nid] for nid in scc_node_ids if nid in idx]
    
    result = compute_kappa_matrix(adj, len(node_list), scc_indices)
    
    # Translate back to node IDs
    fault_lines = []
    if result['min_cut_partition']:
        A_ids = [node_list[i] for i in result['min_cut_partition'][0]]
        B_ids = [node_list[i] for i in result['min_cut_partition'][1]]
        # Identify the actual minimum-direction edges
        set_A = set(result['min_cut_partition'][0])
        set_B = set(result['min_cut_partition'][1])
        if result['min_cut_edges_ab'] <= result['min_cut_edges_ba']:
            for a in result['min_cut_partition'][0]:
                for b in result['min_cut_partition'][1]:
                    if adj[a][b]:
                        fault_lines.append((node_list[a], node_list[b]))
        else:
            for b in result['min_cut_partition'][1]:
                for a in result['min_cut_partition'][0]:
                    if adj[b][a]:
                        fault_lines.append((node_list[b], node_list[a]))
    else:
        A_ids, B_ids = [], []
    
    return {
        'kappa': result['kappa'],
        'scc_nodes': scc_node_ids,
        'min_cut_partition': (A_ids, B_ids) if result['min_cut_partition'] else None,
        'fault_line_edges': fault_lines,
    }


# ═══════════════════════════════════════════════════════════════
# PART 4: TOPOLOGY ANALYSIS (The Full Routing Computation)
# ═══════════════════════════════════════════════════════════════

def analyze_topology(graph: DirectedGraph) -> dict:
    """Full topology analysis for κ-aware routing.
    
    This is the primary function called by Graphonomous at query time.
    It returns everything needed for the κ router to make a decision.
    
    Returns:
        {
            'sccs': [
                {
                    'id': 'scc-0',
                    'nodes': [...],
                    'kappa': int,
                    'min_cut_partition': (list, list) or None,
                    'fault_line_edges': [...],
                    'routing': 'deliberate' or 'retrieve',
                    'deliberation_budget': {...}
                },
                ...
            ],
            'dag_nodes': [...],  # nodes not in any nontrivial SCC
            'routing': 'fast' or 'deliberate',
            'max_kappa': int,
            'scc_count': int,
            'total_nodes': int,
            'total_edges': int,
        }
    """
    sccs = tarjan_scc_graph(graph)
    
    scc_results = []
    scc_node_set = set()
    max_kappa = 0
    
    for i, scc in enumerate(sccs):
        if len(scc) <= 1:
            continue  # trivial SCC (single node), part of DAG
        
        scc_node_set.update(scc)
        kappa_result = compute_kappa_graph(graph, scc)
        k = kappa_result['kappa']
        max_kappa = max(max_kappa, k)
        
        scc_results.append({
            'id': f'scc-{i}',
            'nodes': scc,
            'kappa': k,
            'min_cut_partition': kappa_result['min_cut_partition'],
            'fault_line_edges': kappa_result['fault_line_edges'],
            'routing': 'deliberate' if k > 0 else 'retrieve',
            'deliberation_budget': deliberation_budget(k) if k > 0 else None,
        })
    
    dag_nodes = sorted(graph.nodes - scc_node_set)
    total_edges = sum(len(dsts) for dsts in graph.edges.values())
    
    return {
        'sccs': scc_results,
        'dag_nodes': dag_nodes,
        'routing': 'deliberate' if any(s['kappa'] > 0 for s in scc_results) else 'fast',
        'max_kappa': max_kappa,
        'scc_count': len(scc_results),
        'total_nodes': len(graph.nodes),
        'total_edges': total_edges,
    }


def deliberation_budget(kappa: int) -> dict:
    """Map κ to deliberation parameters.
    
    This is an engineering heuristic, not a proved result.
    Tune empirically.
    """
    return {
        'max_iterations': kappa + 1,
        'agent_count': min(kappa, 3),
        'timeout_multiplier': 1.0 + 0.5 * kappa,
        'confidence_threshold': 0.7 + 0.05 * kappa,
    }


def preview_edge_impact(graph: DirectedGraph, src: str, dst: str) -> dict:
    """Preview the topological impact of adding an edge.
    
    Used by BendScript to show topology-aware suggestions before
    the user commits an edge.
    
    Returns:
        {
            'creates_new_scc': bool,
            'enlarges_existing_scc': bool,
            'kappa_before': int or None,
            'kappa_after': int or None,
            'kappa_delta': int,
            'description': str,
        }
    """
    # Analyze before
    before = analyze_topology(graph)
    before_max_k = before['max_kappa']
    before_scc_count = before['scc_count']
    
    # Temporarily add edge
    graph.add_edge(src, dst)
    after = analyze_topology(graph)
    after_max_k = after['max_kappa']
    after_scc_count = after['scc_count']
    
    # Remove the temporary edge
    graph.remove_edge(src, dst)
    
    creates_new = after_scc_count > before_scc_count
    enlarges = after_max_k > before_max_k and not creates_new
    
    # Generate human-readable description
    if creates_new:
        new_sccs = [s for s in after['sccs'] if s['kappa'] > 0]
        if new_sccs:
            desc = (f"This edge creates a feedback loop (new SCC with κ={new_sccs[-1]['kappa']}). "
                    f"The AI will deliberate on this cluster instead of just retrieving.")
        else:
            desc = "This edge creates a new strongly connected component."
    elif enlarges:
        desc = (f"This edge strengthens an existing feedback loop. "
                f"κ increases from {before_max_k} to {after_max_k}.")
    elif after_max_k == before_max_k and after_scc_count == before_scc_count:
        desc = "This edge has no topological impact on routing."
    else:
        desc = "This edge modifies the graph structure."
    
    return {
        'creates_new_scc': creates_new,
        'enlarges_existing_scc': enlarges,
        'kappa_before': before_max_k,
        'kappa_after': after_max_k,
        'kappa_delta': after_max_k - before_max_k,
        'description': desc,
    }


# ═══════════════════════════════════════════════════════════════
# PART 5: EXHAUSTIVE PROOF VERIFICATION
# ═══════════════════════════════════════════════════════════════

def _adj_matrix_from_bits(n, edge_bits):
    """Convert edge bitmask to adjacency matrix (no self-loops)."""
    m = [[0]*n for _ in range(n)]
    bit = 0
    for i in range(n):
        for j in range(n):
            if i != j:
                if edge_bits & (1 << bit):
                    m[i][j] = 1
                bit += 1
    return m


def _betti1(adj, n):
    """β₁ of largest SCC = |E_scc| - |V_scc| + 1."""
    sccs = tarjan_scc_matrix(adj, n)
    max_b1 = 0
    for scc in sccs:
        if len(scc) <= 1:
            continue
        edges = sum(1 for i in scc for j in scc if adj[i][j] and i != j)
        b1 = edges - len(scc) + 1
        max_b1 = max(max_b1, b1)
    return max_b1


def _has_nontrivial_scc(adj, n):
    sccs = tarjan_scc_matrix(adj, n)
    return any(len(s) > 1 for s in sccs)


def _kappa_matrix_global(adj, n):
    """κ for the full graph (finds largest SCC, computes κ on it)."""
    sccs = tarjan_scc_matrix(adj, n)
    best_scc = max(sccs, key=len) if sccs else []
    if len(best_scc) <= 1:
        return 0
    result = compute_kappa_matrix(adj, n, best_scc)
    return result['kappa']


def verify_graphs(max_n=5):
    """Verify: κ(G) > 0 ⟺ β₁(G) > 0 ⟺ has nontrivial SCC for all graphs n=2..max_n."""
    results = {}
    total_graphs = 0
    total_failures = 0

    for n in range(2, max_n + 1):
        slots = n * (n - 1)
        num_graphs = 1 << slots
        fails = 0
        sc_count = 0
        kappa_beta_pairs = []
        t0 = time.time()

        for bits in range(num_graphs):
            adj = _adj_matrix_from_bits(n, bits)
            k = _kappa_matrix_global(adj, n)
            b = _betti1(adj, n)
            scc = _has_nontrivial_scc(adj, n)

            k_pos, b_pos = k > 0, b > 0
            if k_pos != b_pos or k_pos != scc:
                fails += 1

            if scc:
                sc_count += 1
                kappa_beta_pairs.append((k, b))

        elapsed = time.time() - t0
        total_graphs += num_graphs

        r = None
        if len(kappa_beta_pairs) > 1:
            ks = [x[0] for x in kappa_beta_pairs]
            bs = [x[1] for x in kappa_beta_pairs]
            mk, mb = sum(ks)/len(ks), sum(bs)/len(bs)
            cov = sum((k-mk)*(b-mb) for k,b in zip(ks,bs))
            vk = sum((k-mk)**2 for k in ks) ** 0.5
            vb = sum((b-mb)**2 for b in bs) ** 0.5
            r = cov / (vk * vb) if vk > 0 and vb > 0 else 0

        results[n] = {
            'num_graphs': num_graphs, 'sc_graphs': sc_count,
            'failures': fails, 'pearson_r': round(r, 4) if r else None,
            'elapsed_ms': round(elapsed * 1000),
        }
        status = "PASS" if fails == 0 else "FAIL"
        print(f"  n={n}: {num_graphs:>10} graphs, {sc_count:>8} SC, "
              f"fails={fails}, r(κ,β₁)={f'{r:.4f}' if r else 'N/A':>6}, "
              f"{elapsed*1000:.0f}ms [{status}]")
        total_failures += fails

    return results, total_graphs, total_failures


def verify_dynamical_systems(max_n=7):
    """Verify: κ(f) > 0 ⟺ f has periodic orbit of period > 1 for all f:[n]→[n]."""
    results = {}
    total_maps = 0
    total_failures = 0

    for n in range(2, max_n + 1):
        num_maps = n ** n
        fails = 0
        periodic_count = 0
        t0 = time.time()

        for f_tuple in cart_product(range(n), repeat=n):
            f_map = list(f_tuple)
            
            # Check periodic orbit
            has_po = False
            for x in range(n):
                visited = set()
                curr = x
                while curr not in visited:
                    visited.add(curr)
                    curr = f_map[curr]
                cycle_start = curr
                cycle_len = 1
                c = f_map[curr]
                while c != cycle_start:
                    cycle_len += 1
                    c = f_map[c]
                if cycle_len > 1:
                    has_po = True
                    break
            
            # Build transition graph and compute κ
            adj = [[0]*n for _ in range(n)]
            for i in range(n):
                if f_map[i] != i:
                    adj[i][f_map[i]] = 1
            k = _kappa_matrix_global(adj, n)
            
            if (k > 0) != has_po:
                fails += 1
            if has_po:
                periodic_count += 1

        elapsed = time.time() - t0
        total_maps += num_maps
        results[n] = {
            'num_maps': num_maps, 'periodic_maps': periodic_count,
            'failures': fails, 'elapsed_ms': round(elapsed * 1000),
        }
        status = "PASS" if fails == 0 else "FAIL"
        print(f"  n={n}: {num_maps:>8} maps, {periodic_count:>7} periodic, "
              f"fails={fails}, {elapsed*1000:.0f}ms [{status}]")
        total_failures += fails

    return results, total_maps, total_failures


# ═══════════════════════════════════════════════════════════════
# PART 6: DEMO / CLI
# ═══════════════════════════════════════════════════════════════

def demo_knowledge_graph():
    """Demonstrate κ-aware routing on a sample knowledge graph."""
    print("\n" + "=" * 60)
    print("DEMO: κ-Aware Routing on a Knowledge Graph")
    print("=" * 60)
    
    g = DirectedGraph()
    
    # DAG region: simple factual chain
    g.add_edge("company", "founded-2020", {"kind": "temporal"})
    g.add_edge("company", "hq-austin", {"kind": "spatial"})
    g.add_edge("company", "ceo-alice", {"kind": "associative"})
    
    # SCC region: mutually dependent business concepts
    g.add_edge("market-share", "revenue", {"kind": "causal"})
    g.add_edge("revenue", "r-and-d", {"kind": "causal"})
    g.add_edge("r-and-d", "product-quality", {"kind": "causal"})
    g.add_edge("product-quality", "market-share", {"kind": "causal"})  # closes the loop
    g.add_edge("market-share", "customer-retention", {"kind": "causal"})
    g.add_edge("customer-retention", "revenue", {"kind": "causal"})  # second loop
    
    # Connect DAG to SCC
    g.add_edge("company", "market-share", {"kind": "associative"})
    
    # Analyze
    result = analyze_topology(g)
    
    print(f"\nGraph: {result['total_nodes']} nodes, {result['total_edges']} edges")
    print(f"Overall routing: {result['routing'].upper()}")
    print(f"Max κ: {result['max_kappa']}")
    print(f"SCCs with feedback: {result['scc_count']}")
    
    print(f"\nDAG nodes (fast retrieval): {result['dag_nodes']}")
    
    for scc in result['sccs']:
        print(f"\n  SCC '{scc['id']}':")
        print(f"    Nodes: {scc['nodes']}")
        print(f"    κ = {scc['kappa']}")
        print(f"    Routing: {scc['routing']}")
        print(f"    Fault lines: {scc['fault_line_edges']}")
        if scc['deliberation_budget']:
            b = scc['deliberation_budget']
            print(f"    Deliberation budget: {b['max_iterations']} iterations, "
                  f"{b['agent_count']} agents, "
                  f"{b['confidence_threshold']:.2f} confidence threshold")
    
    # Preview edge impact
    print(f"\n--- Edge Impact Preview ---")
    preview = preview_edge_impact(g, "ceo-alice", "r-and-d")
    print(f"  Adding edge ceo-alice → r-and-d:")
    print(f"    {preview['description']}")
    print(f"    κ: {preview['kappa_before']} → {preview['kappa_after']} (Δ{preview['kappa_delta']})")


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == '--verify':
        print("=" * 60)
        print("EXHAUSTIVE PROOF: THE CYCLICITY INVARIANT κ")
        print("=" * 60)
        print()
        print("PART 1: DIRECTED GRAPHS (n=2..5)")
        print("  Verifying: κ(G) > 0 ⟺ β₁(G) > 0 ⟺ has nontrivial SCC")
        print("-" * 60)
        g_results, g_total, g_fails = verify_graphs(5)
        
        print()
        print("PART 2: FINITE DYNAMICAL SYSTEMS (n=2..7)")
        print("  Verifying: κ(f) > 0 ⟺ has periodic orbit (period > 1)")
        print("-" * 60)
        d_results, d_total, d_fails = verify_dynamical_systems(7)
        
        print()
        print("=" * 60)
        total = g_total + d_total
        fails = g_fails + d_fails
        if fails == 0:
            print(f"VERIFIED: {total:,} objects tested, 0 counterexamples.")
        else:
            print(f"FAILED: {fails} counterexamples in {total:,} objects.")
        print("=" * 60)
    
    elif len(sys.argv) > 1 and sys.argv[1] == '--demo':
        demo_knowledge_graph()
    
    else:
        print("Usage:")
        print("  python kappa_reference.py --verify   Run exhaustive proof (1,926,351 objects)")
        print("  python kappa_reference.py --demo     Demo κ-aware routing on sample graph")
        print()
        # Default: run demo
        demo_knowledge_graph()
