/* acceptance.mjs — A1–A7 as ONE executable definition, shared by the CLI, the tests and the G0.5 page.
 *
 * Each question is a pure function of a `Graph` (lib/query.mjs) and returns a *result record*: a list of typed steps,
 * each of which is either a set of lids, a set of derived facts, or an explanation tree. Nothing here computes a fact
 * the projection and its evaluation do not already hold — every step is one of the six query functions
 * (node · neighbors · path · facts · explain · as_of). No prose is invented: a step's `label` names the traversal, and
 * its `value` is records.
 *
 * Why this module exists: GPT v5 §10 requires A1–A7 to be reachable from the read-only UI, and forbids the UI from
 * showing an answer that is not the deterministic one. Baking the answers into the page from a *different* code path
 * than the tests would make the screen unfalsifiable. So the page, `g0 acceptance` and `test/acceptance.test.mjs` all
 * call THESE functions; the page never re-derives, it renders what this module returned in Node.
 *
 * Snapshot scope: a question declares which snapshots it can answer (`needs`). A1/A3/A5/A6 read one graph; A2 and A4
 * compare two pins and are answered only when both are loaded. A question that cannot run on a selection says so —
 * it never silently answers from the wrong root. */

export const S6 = "obligation:inv:S6%3F", S1 = "obligation:inv:S1", S5 = "obligation:inv:S5";
export const R08 = "round:computedriven:R0.8";
export const R085 = "receipt:sha256:6ba8544cbf7c91ef526ddde97943d54845e1f352814173b8fa9a64f86867a913";
export const R086 = "receipt:sha256:cffc0218fc450884ad2bf4d1630468c675b262e8260ef72b8c90dbf061016303";

/** Walk an explanation tree and collect every leaf: base facts (with their sources) and absences. */
export const leaves = (node, acc = []) => {
  if (!node) return acc;
  if (node.basis === "absent" || node.basis === "base") acc.push(node);
  else if (node.premises) for (const p of node.premises) leaves(p, acc);
  else if (node.derivations) for (const d of node.derivations) leaves(d, acc);
  return acc;
};

const step = (label, call, kind, value) => ({ label, call, kind, value });
const lids = (xs) => xs.map((x) => (typeof x === "string" ? x : x.lid));

/* Each entry: id, title, question (the human sentence GPT v5 §10.7 names), needs (snapshot roles), run(graphs). */
export const QUESTIONS = [
  {
    id: "A1", needs: ["primary"],
    title: "why S6? is not primitive",
    question: "Why isn't S6? a primitive obligation?",
    proves: "an explanation is a derivation path over stored records, not recollection",
    run: ({ primary: g }) => {
      const facts = g.facts("not_primitive");
      const ex = g.explain(["not_primitive", S6]);
      const base = leaves(ex);
      const relLeaf = base.find((l) => l.fact?.[0] === "rel") || null;
      return [
        step("derived not_primitive facts", `facts("not_primitive")`, "facts", facts),
        step("the derivation tree", `explain(["not_primitive","${S6}"])`, "explain", ex),
        step("what it reduces to", `neighbors("${S6}","REDUCES_TO","out")`, "lids", lids(g.neighbors(S6, "REDUCES_TO", "out").map((n) => n.other))),
        step("the source pointer the derivation bottoms out in", "leaves(explain)", "locations",
          relLeaf ? (relLeaf.source?.assertions || []).map((a) => ({ assertion: a.lid, location: a.location })) : []),
        step("S6?'s own record", `node("${S6}")`, "record", g.node(S6)),
      ];
    },
  },
  {
    id: "A2", needs: ["primary", "compare"],
    title: "what opens R0.8, by snapshot",
    question: "What findings does round R0.8 open — and does the answer depend on which snapshot you ask?",
    proves: "history is kept: an answer is snapshot-relative and never mixes two roots",
    run: ({ primary: g, compare: h }) => {
      const opensG = g.neighbors(R08, "OPENS", "out"), opensH = h ? h.neighbors(R08, "OPENS", "out") : [];
      const first = opensG[0] || null;
      return [
        step(`opened at ${g.snapshot}`, `as_of(…).neighbors("${R08}","OPENS","out")`, "lids", lids(opensG.map((n) => n.other))),
        ...(h ? [step(`opened at ${h.snapshot}`, `as_of(…).neighbors("${R08}","OPENS","out")`, "lids", lids(opensH.map((n) => n.other)))] : []),
        step("what the unnamed finding cites", first ? `neighbors("${first.other}","CITES","out")` : "—", "lids",
          first ? lids(g.neighbors(first.other, "CITES", "out").map((n) => n.other)) : []),
        step("one OPENS relation, both registries", first ? `explain("${first.relation.lid}")` : "—", "explain",
          first ? g.explain(first.relation.lid) : null),
      ];
    },
  },
  {
    id: "A3", needs: ["primary"],
    title: "what supports S5",
    question: "What supports obligation S5, and is any of it backed by an executed receipt?",
    proves: "an obligation is explained end to end from provenance, including the executed flag on the assertion",
    run: ({ primary: g }) => {
      const into = g.neighbors(S5, null, "in");
      const observed = g.facts("exec_receipt_observed");
      const subject = observed.find((f) => f.args[0] === "claim:crosswalk:E-48") ? "claim:crosswalk:E-48" : observed[0]?.args[0];
      const ex = subject ? g.explain(["has_exec_receipt", subject]) : null;
      return [
        step("everything pointing at S5", `neighbors("${S5}",null,"in")`, "edges",
          into.map((n) => ({ kind: n.relation.kind, other: n.other, relation: n.relation.lid }))),
        step("claims with an observed execution receipt", `facts("exec_receipt_observed")`, "facts", observed),
        step(subject ? `why ${subject} has one` : "—", subject ? `explain(["has_exec_receipt","${subject}"])` : "—", "explain", ex),
      ];
    },
  },
  {
    id: "A4", needs: ["primary", "compare"],
    title: "E-13b witness movement",
    question: "How did E-13b's witness provenance change between the two pins?",
    proves: "supersession never deletes: the older pin's answer is still answerable at the older root",
    run: ({ primary: g, compare: h }) => {
      const claims = (gr, rc) => gr.neighbors(rc, "WITNESSES", "out").map((n) => n.other).filter((x) => x.startsWith("claim:")).sort();
      const rel = g.facts("WITNESSES", { source: R085, target: "claim:crosswalk:E-14" });
      return [
        step(`R0.8.5 handback witnesses, at ${g.snapshot}`, `neighbors("${R085}","WITNESSES","out")`, "lids", claims(g, R085)),
        ...(h ? [step(`the same receipt at ${h.snapshot}`, `as_of(…).neighbors("${R085}","WITNESSES","out")`, "lids", claims(h, R085))] : []),
        step(`R0.8.6 handback witnesses, at ${g.snapshot}`, `neighbors("${R086}","WITNESSES","out")`, "lids", claims(g, R086)),
        step("the roles live on the assertions, not the relation", rel[0] ? `explain("${rel[0].lid}")` : "—", "explain", rel[0] ? g.explain(rel[0].lid) : null),
      ];
    },
  },
  {
    id: "A5", needs: ["primary"],
    title: "mechanism evidence",
    question: "Which mechanisms are represented, and on what evidence?",
    proves: "a MECHANISM exists only where the source named a symbol; mechanism_of derives only from typed relation records",
    run: ({ primary: g }) => {
      const mechs = g.facts("MECHANISM");
      const mo = g.facts("mechanism_of");
      return [
        step("MECHANISM nodes", `facts("MECHANISM")`, "lids", lids(mechs)),
        step("derived mechanism_of", `facts("mechanism_of")`, "facts", mo),
        step("each mechanism's source symbol", `neighbors(m,"LOCATED_IN","out")`, "locations",
          mechs.map((m) => {
            const n = g.neighbors(m.lid, "LOCATED_IN", "out")[0];
            return { mechanism: m.lid, location: n ? g.locations.get(n.other) || { lid: n.other } : null };
          })),
        step("one mechanism_of, explained", mo[0] ? `explain(["mechanism_of", …])` : "—", "explain", mo[0] ? g.explain([mo[0].rel, ...mo[0].args]) : null),
      ];
    },
  },
  {
    id: "A6", needs: ["primary"],
    title: "receipt-observability partition",
    question: "For each tested claim, is an execution receipt observed, observed-absent, or undecidable from the source?",
    proves: "absence is asserted only where it is decidable; the source's silence is never read as a negative",
    run: ({ primary: g }) => {
      const undecidable = g.facts("exec_receipt_undecidable_from_source");
      const pick = undecidable[0];
      const ex = pick ? g.explain([pick.rel, ...pick.args]) : null;
      return [
        step("observed", `facts("exec_receipt_observed")`, "facts", g.facts("exec_receipt_observed")),
        step("observed absent", `facts("no_exec_receipt_observed")`, "facts", g.facts("no_exec_receipt_observed")),
        step("undecidable from the source", `facts("exec_receipt_undecidable_from_source")`, "facts", undecidable),
        step("tested claims", `facts("tested_claim")`, "facts", g.facts("tested_claim")),
        step("why one is undecidable — the absence is a premise, and it names what is absent", pick ? `explain(["${pick.rel}", …])` : "—", "explain", ex),
        step("the absences in that tree", "leaves(explain).filter(absent)", "absences", ex ? leaves(ex).filter((l) => l.basis === "absent").map((l) => l.absent) : []),
      ];
    },
  },
  {
    id: "A7", needs: ["primary"],
    title: "source-grounded explanation (exhaustive)",
    question: "Does every relation and every derived fact explain down to exact source assertions and pinned locations?",
    proves: "no answer on the screen rests on anything but a pinned source byte",
    run: ({ primary: g }) => {
      let rels = 0, relAssertions = 0, badLoc = 0;
      const precisions = new Map();
      for (const r of g.relations.values()) {
        const ex = g.explain(r.lid); rels++; relAssertions += ex.assertions.length;
        for (const a of ex.assertions) {
          if (a.location.missing || !/^[0-9a-f]{40}$|^sha256:/.test(a.location.pinned_identity || "")) badLoc++;
          precisions.set(a.location.precision, (precisions.get(a.location.precision) || 0) + 1);
        }
      }
      let facts = 0, baseLeaves = 0, unsourced = 0;
      if (g.derived) for (const f of g.derived.facts) {
        const ls = leaves(g.explain([f.rel, ...f.args])); facts++;
        for (const l of ls) if (l.basis === "base") { baseLeaves++; if (!l.source || l.source.missing) unsourced++; }
      }
      return [
        step("relations explained", "for each relation: explain(lid)", "counts",
          { relations: rels, assertions: relAssertions, assertions_without_a_pinned_location: badLoc }),
        step("assertion location precision", "explain(lid).assertions[].location.precision", "counts", Object.fromEntries([...precisions].sort())),
        step("derived facts explained", "for each fact: explain([rel,...args])", "counts",
          { facts, base_leaves: baseLeaves, base_leaves_without_a_source: unsourced }),
        step("the claim this makes", "—", "verdict",
          badLoc === 0 && unsourced === 0
            ? "every relation and every derived fact bottoms out in a pinned source location"
            : `NOT HELD: ${badLoc} assertion(s) without a pinned location, ${unsourced} base leaf/leaves without a source`),
      ];
    },
  },
];

export const questionById = (id) => QUESTIONS.find((q) => q.id === id) || null;

/** Run every question that the given graph selection can answer. `graphs` = {primary, compare?}. */
export function runAcceptance(graphs) {
  return QUESTIONS.map((q) => {
    const missing = q.needs.filter((n) => !graphs[n]);
    if (missing.length) return { id: q.id, title: q.title, question: q.question, proves: q.proves, answered: false, reason: `needs a ${missing.join(" and ")} snapshot; not answered from the wrong root` };
    let steps, error = null;
    try { steps = q.run(graphs); } catch (e) { error = e.message; steps = []; }
    return { id: q.id, title: q.title, question: q.question, proves: q.proves, answered: !error, ...(error ? { reason: error } : {}), snapshot: graphs.primary.snapshot, compare: graphs.compare?.snapshot ?? null, steps };
  });
}
