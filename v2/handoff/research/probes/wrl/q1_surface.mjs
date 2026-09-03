import * as W from "/home/travis/ProjectAmp2/WRL/wrl.js";
const P = "profile forge.world.core.v1\n";
const cases = {
  "role claim":            P + "[claim:c1]\n",
  "role claim w/ ports":   P + "[claim:c1]{out}\n",
  "edge tag supports":     P + "[pulser:p0](every 2){sig_out}\n[relay:r0]{sig_in, sig_out}\n[p0] --supports--> [r0]\n",
  "edge tag SUPPORTS uc":  P + "[pulser:p0](every 2){sig_out}\n[relay:r0]{sig_in, sig_out}\n[p0] --SUPPORTS--> [r0]\n",
  "new profile id":        "profile graphonomous.g0.v1\n[relay:r0]{sig_in, sig_out}\n",
  "relay config key":      P + "[relay:r0](evidence_state=open){sig_in, sig_out}\n",
  "attributed edge":       P + "[pulser:p0](every 2){sig_out}\n[relay:r0]{sig_in, sig_out}\n[p0] --sig(weight=1)--> [r0]\n",
  "qualified kind":        P + "[pulser:p0](every 2){sig_out}\n[relay:r0]{sig_in, sig_out}\n[p0] --evidence.supports--> [r0]\n",
  "async texture ~~":      P + "[pulser:p0](every 2){sig_out}\n[relay:r0]{sig_in, sig_out}\n[p0] ~~sig~~> [r0]\n",
  "verified texture ==":   P + "[pulser:p0](every 2){sig_out}\n[relay:r0]{sig_in, sig_out}\n[p0] ==sig==> [r0]\n",
  "ports-free relay {}":   P + "[relay:r0]{}\n",
  "relay no brace group":  P + "[relay:r0]\n",
  "empty world":           P,
  "no profile":            "[relay:r0]{sig_in, sig_out}\n",
  "ir 2.0 through V1 spine": P + "ir 2.0\n",
  "id with __":            P + "[relay:a__b]{sig_in, sig_out}\n",
  "id with dash":          P + "[relay:claim-1]{sig_in, sig_out}\n",
  "hash marker":           P + "[relay:r0]{sig_in, sig_out} # not a comment\n",
};
for (const [n, s] of Object.entries(cases)) {
  const r = await W.sealWorld(s);
  console.log(`${n.padEnd(26)} => ${r.ok ? r.semanticId : `${r.code} @line ${r.line}: ${r.message}`}`);
}
console.log("\nROLE_IDS         ", JSON.stringify(W.ROLE_IDS));
console.log("SURFACE_ROLE_IDS ", JSON.stringify(W.SURFACE_ROLE_IDS));
console.log("UNWRITABLE_ROLES ", JSON.stringify(W.UNWRITABLE_ROLE_IDS));
console.log("EDGE_KINDS       ", JSON.stringify(W.EDGE_KINDS));
console.log("EDGE_PORTS       ", JSON.stringify(W.EDGE_PORTS));
console.log("PORTS            ", JSON.stringify(W.PORTS));
console.log("ROLE_CONFIG      ", JSON.stringify(W.ROLE_CONFIG_SCHEMA));
console.log("PROFILE_ID       ", W.PROFILE_ID, "| RULEPACK", W.RULEPACK_ID, "| IR", W.IR_VERSION, W.IR_VERSION_V1_1);
console.log("CODES total      ", Object.keys(W.CODES).length, "| browser-raisable", W.BROWSER_CODE_IDS.length);
console.log("frozen? ROLE_IDS", Object.isFrozen(W.ROLE_IDS), "PORTS", Object.isFrozen(W.PORTS));
