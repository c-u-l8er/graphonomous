// PROBE B — three canonicalizers on the same values: TRVM canonicalBytes, WRL serializeArtifact (JS), Python json.dumps(sort_keys, compact)
import { canonicalBytes } from "/home/travis/ProjectAmp2/TRVM/governance/derive_protocol.mjs";
import { execFileSync } from "node:child_process";
let wrl = null;
try { wrl = await import("/home/travis/ProjectAmp2/WRL/wrl.js"); console.log("WRL/wrl.js imported; exports serializeArtifact:", typeof wrl.serializeArtifact); }
catch (e) { console.log("WRL/wrl.js import FAILED:", e.message.slice(0, 200)); }

const cases = [
  ["key order", { b: 1, a: 2 }],
  ["nested", { z: [3, { y: 1, x: 2 }], a: null, t: true }],
  ["float 1.5", { a: 1.5 }],
  ["float 0.1", { a: 0.1 }],
  ["1e21", { a: 1e21 }],
  ["1e-7", { a: 1e-7 }],
  ["-0", { a: -0 }],
  ["2^53", { a: 9007199254740992 }],
  ["2^60 as Number", { a: 2 ** 60 }],
  ["BigInt 2^60", { a: 2n ** 60n }],
  ["unicode e-acute", { a: "é" }],
  ["control 0x7f", { a: "\x7f" }],
  ["U+0080", { a: "\x80" }],
  ["emoji key vs U+FB33 key", { "\u{1F602}": 1, "דּ": 2 }],
  ["escapes", { a: "\"\\\n\t/" }],
  ["lone surrogate", { a: "\uD800" }],
  ["NaN", { a: NaN }],
];
const py = (obj) => {
  const src = JSON.stringify(obj, (k, v) => typeof v === "bigint" ? "__BIGINT__" + v.toString() : v);
  const code = `import json,sys
o=json.loads(sys.stdin.read())
def fix(x):
    if isinstance(x,str) and x.startswith("__BIGINT__"): return int(x[10:])
    if isinstance(x,dict): return {k:fix(v) for k,v in x.items()}
    if isinstance(x,list): return [fix(v) for v in x]
    return x
o=fix(o)
a=json.dumps(o, sort_keys=True, separators=(",",":"))
b=json.dumps(o, sort_keys=True, separators=(",",":"), ensure_ascii=False)
sys.stdout.write(a + ("" if a==b else "   [ensure_ascii=False: " + b + "]"))`;
  try { return execFileSync("python3", ["-c", code], { input: src, encoding: "utf8" }); }
  catch (e) { return "PY-ERR " + (e.stderr || e.message).toString().trim().split("\n").pop(); }
};
const show = (s) => typeof s === "string" ? JSON.stringify(s).slice(1, -1).replace(/\\"/g, '"') : String(s);
for (const [label, v] of cases) {
  let t, w, p;
  try { t = canonicalBytes(v); } catch (e) { t = "REFUSED " + e.message; }
  try { w = wrl ? wrl.serializeArtifact(v) : "n/a"; } catch (e) { w = "REFUSED " + (e.code ? e.code + " " : "") + String(e.message).slice(0, 80); }
  if (label === "lone surrogate") p = "PY: json.dumps → " + show(py({ a: "\uD800" }).replace(/\n/g, ""));
  else if (label === "NaN") p = "PY: json.dumps(float('nan')) → NaN (emitted, allow_nan=True default)";
  else p = py(v);
  console.log(`\n== ${label} ==\n  TRVM canonicalBytes  : ${show(t)}\n  WRL serializeArtifact: ${show(w)}\n  Python json.dumps    : ${show(p)}`);
}
// python NaN check for real
console.log("\npython NaN:", execFileSync("python3", ["-c", "import json; print(json.dumps({'a': float('nan')}, sort_keys=True, separators=(',',':')))"], { encoding: "utf8" }).trim());
console.log("python lone surrogate:", execFileSync("python3", ["-c", "import json; print(json.dumps({'a': '\\ud800'}, sort_keys=True, separators=(',',':')))"], { encoding: "utf8" }).trim());
console.log("python float 1e21:", execFileSync("python3", ["-c", "import json; print(json.dumps({'a': 1e21}, sort_keys=True, separators=(',',':')))"], { encoding: "utf8" }).trim());
console.log("python float 1e-7:", execFileSync("python3", ["-c", "import json; print(json.dumps({'a': 1e-7}, sort_keys=True, separators=(',',':')))"], { encoding: "utf8" }).trim());
console.log("python -0.0:", execFileSync("python3", ["-c", "import json; print(json.dumps({'a': -0.0}, sort_keys=True, separators=(',',':')))"], { encoding: "utf8" }).trim());
console.log("python 2**60 int:", execFileSync("python3", ["-c", "import json; print(json.dumps({'a': 2**60}, sort_keys=True, separators=(',',':')))"], { encoding: "utf8" }).trim());
