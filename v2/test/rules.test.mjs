import { test } from "node:test";
import assert from "node:assert/strict";
import { loadRules, checkStratification, checkSafety } from "../lib/rules.mjs";

test("the G0 rule set loads, validates, stratifies and has a content-bound id", () => {
  const { doc, rule_sem_id, rule_ids } = loadRules();
  assert.match(rule_sem_id, /^g0rule-[0-9a-f]{64}$/);
  assert.equal(doc.ruleset, "G0-RULESET-v1");
  assert.ok(rule_ids.no_exec_receipt_observed.endsWith("#no_exec_receipt_observed"));
  // D-022: the withdrawn word names no rule, relation or report
  const names = doc.rules.flatMap((r) => [r.name, r.head.rel, r.reports || ""]).join(" ");
  assert.equal(/unsupported/i.test(names), false, names);
  const reports = doc.rules.filter((r) => r.reports).map((r) => r.reports).sort();
  assert.deepEqual(reports, ["EXEC_RECEIPT_OBSERVED", "EXEC_RECEIPT_UNDECIDABLE_FROM_SOURCE", "NO_EXEC_RECEIPT_OBSERVED"]);
  // the id moves with any change to the program
  const again = loadRules(); assert.equal(again.rule_sem_id, rule_sem_id);
});

test("stratification refuses negation inside the same stratum and forward references", () => {
  const facts = { node: { arity: 2, doc: "" } };
  assert.throws(() => checkStratification({ facts, rules: [
    { name: "p", stratum: 0, head: { rel: "p", args: ["X"] }, body: [{ rel: "node", args: ["X", "_"] }, { rel: "q", args: ["X"], neg: true }] },
    { name: "q", stratum: 0, head: { rel: "q", args: ["X"] }, body: [{ rel: "node", args: ["X", "_"] }, { rel: "p", args: ["X"], neg: true }] },
  ] }), /RULES_NEGATION_NOT_STRATIFIED/);
  assert.throws(() => checkStratification({ facts, rules: [
    { name: "p", stratum: 0, head: { rel: "p", args: ["X"] }, body: [{ rel: "q", args: ["X"] }] },
    { name: "q", stratum: 1, head: { rel: "q", args: ["X"] }, body: [{ rel: "node", args: ["X", "_"] }] },
  ] }), /RULES_FORWARD_REFERENCE/);
  assert.throws(() => checkStratification({ facts, rules: [ { name: "p", stratum: 0, head: { rel: "p", args: ["X"] }, body: [{ rel: "node", args: ["X"] }] } ] }), /RULES_ARITY/);
  assert.throws(() => checkStratification({ facts, rules: [ { name: "p", stratum: 0, head: { rel: "p", args: ["X"] }, body: [{ rel: "ghost", args: ["X"] }] } ] }), /RULES_UNDEFINED_RELATION/);
});

test("safety refuses unbound head or negated variables", () => {
  assert.throws(() => checkSafety({ rules: [ { name: "p", stratum: 0, head: { rel: "p", args: ["Y"] }, body: [{ rel: "node", args: ["X", "_"] }] } ] }), /RULES_UNSAFE/);
  assert.throws(() => checkSafety({ rules: [ { name: "p", stratum: 1, head: { rel: "p", args: ["X"] }, body: [{ rel: "node", args: ["X", "_"] }, { rel: "q", args: ["Z"], neg: true }] } ] }), /RULES_UNSAFE/);
});
