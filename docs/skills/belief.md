---
name: belief
description: Use when knowledge changes, contradictions are detected, facts become outdated, or corrections are needed. Triggers on "revise belief", "correct knowledge", "contradictions", "knowledge is wrong", "update fact", "expand belief", "contract belief", or when learn_from_outcome reveals failures. Uses `act` and `learn` machines.
argument-hint: [expand|revise|contract] <content or node_id>
---

# Belief Revision

AGM-style belief management — expand, revise, or contract beliefs with automatic contradiction detection and confidence propagation.

## Arguments

Operation and target: $ARGUMENTS

## Operations

### Expand — Add a New Belief
```
act(action: "belief_revise", operation: "expand", content: "New fact here", confidence: 0.8)
```
Automatically checks for contradictions. Creates bidirectional `:contradicts` edges if found (forming kappa=1 SCCs).

### Revise — Replace a Wrong Belief
```
act(action: "belief_revise", operation: "revise", node_id: "<old_node>", content: "Corrected fact", rationale: "why")
```
Creates new node, supersedes old (confidence -> 30%), propagates 0.6x decay through dependents.

### Contract — Withdraw Without Replacement
```
act(action: "belief_revise", operation: "contract", node_id: "<wrong_node>", rationale: "why")
```
Sets confidence to 0.05, propagates decay. Node preserved for provenance.

## Detect Contradictions
```
learn(action: "contradictions", content: "<new info>")
learn(action: "contradictions", node_id: "<existing_node>")
```
Returns detected conflicts with similarity scores and negation markers.

## Workflow

1. `learn(action: "contradictions", content: "<new info>")` — check first
2. Assess: is the contradiction real?
3. `act(action: "belief_revise", operation: "revise|contract|expand")` — act
4. `route(action: "topology", ...)` — check for new cycles
5. `route(action: "deliberate", ...)` — if kappa > 0 on affected region
6. `learn(action: "from_outcome", ...)` — report the revision result

## Key Rules

- Always check contradictions before revising
- Use `revise` when old is wrong (not `expand` — that creates contradictions)
- Use `contract` when wrong but no replacement available
- Review `affected_node_ids` after revision to assess cascade impact

## Anti-patterns to avoid

- Expanding without checking for contradictions first
- Using `contract` when you have a correction (use `revise` instead)
- Ignoring cascade effects on dependent nodes
