import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  assertTrvmPinned, TRVM_PIN, parseStrictJson, canonicalBytesG0, canonicalBytesSource, canonicalTextG0, assertG0Value, hashRecord, sortSet,
  leafHashHex, hashOfBytes, naiveCanonicalText, artifactRoot, G0Error, DECIMAL_KEY,
} from "../lib/canon.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const FIX = resolve(HERE, "fixtures/canon");
const TWIN_OUT = resolve(HERE, ".twin-out");
const TWIN = resolve(HERE, "canon_twin.py");
const vectors = JSON.parse(readFileSync(resolve(FIX, "vectors.json"), "utf8")).vectors;
const naivePy = "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.stdout.buffer.write(json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8'))";
const CTRL = String.fromCharCode(1);
const DEL = String.fromCharCode(0x7f);

test("the TRVM canonicalizer and CAS are the pinned blobs", () => {
  const seen = assertTrvmPinned();
  assert.deepEqual(seen, TRVM_PIN.blobs);
});

test("vectors: the strict reader + G0 domain accept/refuse as expected, with the hand-derived canonical text", () => {
  for (const v of vectors) {
    let got = null, err = null;
    try {
      const { value, number_forms } = parseStrictJson(v.text);
      got = canonicalTextG0(value);
      if (v.expect.number_forms) assert.deepEqual(number_forms, v.expect.number_forms, v.name);
    } catch (e) { err = e; }
    if (v.expect.accept) {
      assert.equal(err, null, `${v.name}: unexpected refusal ${err?.message}`);
      if (v.expect.canonical !== undefined) assert.equal(got, v.expect.canonical, v.name);
    } else {
      assert.ok(err instanceof G0Error, `${v.name}: expected a G0Error, got ${err}`);
      assert.equal(err.code, v.expect.refusal, `${v.name}: ${err.message}`);
    }
  }
});

test("vectors: byte-for-byte agreement with the Python twin (files compared, not hashes)", () => {
  rmSync(TWIN_OUT, { recursive: true, force: true }); mkdirSync(TWIN_OUT, { recursive: true });
  execFileSync("python3", [TWIN, "--vectors", resolve(FIX, "vectors.json"), "--out", TWIN_OUT], { stdio: ["ignore", "pipe", "inherit"] });
  let compared = 0;
  for (const v of vectors.filter((x) => x.twin)) {
    const canonPath = resolve(TWIN_OUT, v.name + ".canon"), refusedPath = resolve(TWIN_OUT, v.name + ".refused");
    if (v.expect.accept) {
      assert.ok(existsSync(canonPath), `${v.name}: twin refused what Node accepts`);
      const twinBytes = readFileSync(canonPath);
      const ours = canonicalBytesG0(parseStrictJson(v.text).value);
      assert.ok(ours.equals(twinBytes), `${v.name}: bytes differ\n node: ${ours.toString("utf8")}\n twin: ${twinBytes.toString("utf8")}`);
    } else {
      assert.ok(existsSync(refusedPath), `${v.name}: twin accepted what Node refuses`);
      const code = readFileSync(refusedPath, "utf8").trim();
      assert.equal(code, v.expect.refusal, `${v.name}: twin refusal ${code}`);
    }
    compared++;
  }
  assert.ok(compared >= 20, `only ${compared} vectors compared`);
});

test("the 1.0 divergence: reproduced under the naive discipline, removed under the G0 domain (ledger v2.6 blob b1cdc96b)", () => {
  const raw = readFileSync(resolve(FIX, "ledger-v2.6-b1cdc96b.json"));
  const naiveNode = Buffer.from(naiveCanonicalText(JSON.parse(raw.toString("utf8"))), "utf8");
  assert.match(naiveNode.toString("utf8"), /"confidence":1[,}]/, "naive Node prints 1.0 as 1");
  const { value, number_forms } = parseStrictJson(raw);
  const lex = number_forms.find((f) => f.pointer === "/claims/18/confidence");
  assert.equal(lex?.lexeme, "1.0");
  assert.equal(number_forms.length, 19, "the ledger carries 19 non-integer confidences");
  assert.throws(() => canonicalBytesG0(value), /G0_KEY_GRAMMAR/, "a raw source is never hashed as a record");
  const g0Node = canonicalBytesSource(value);
  assert.match(g0Node.toString("utf8"), /"confidence":\{"decimal_string":"1\.0"\}/);
  rmSync(TWIN_OUT, { recursive: true, force: true }); mkdirSync(TWIN_OUT, { recursive: true });
  const rep = JSON.parse(execFileSync("python3", [TWIN, "--file", resolve(FIX, "ledger-v2.6-b1cdc96b.json"), "--out", TWIN_OUT, "--naive"]).toString("utf8"));
  const twinG0 = readFileSync(resolve(TWIN_OUT, "ledger-v2.6-b1cdc96b.json.canon"));
  const twinNaive = readFileSync(resolve(TWIN_OUT, "ledger-v2.6-b1cdc96b.json.naive.canon"));
  assert.ok(g0Node.equals(twinG0), "G0 canonical bytes must be identical across Node and Python");
  assert.ok(!naiveNode.equals(twinNaive), "the naive discipline must still diverge (that is the finding)");
  assert.equal(twinNaive.length - naiveNode.length, 2, "Python writes 1.0 where Node writes 1: two bytes");
  assert.equal(rep.g0_bytes, g0Node.length);
});

test("the v2.7 crosswalk (blob c7dba29f): no floats, byte-identical naive form across runtimes, but its raw keys fail the G0 key grammar", () => {
  const raw = readFileSync(resolve(FIX, "crosswalk-v2.7-c7dba29f.json"));
  const { value, number_forms } = parseStrictJson(raw);
  assert.equal(number_forms.length, 0, "the crosswalk carries no non-integer numbers");
  assert.throws(() => canonicalBytesG0(value), /G0_KEY_GRAMMAR/);
  const src = canonicalBytesSource(value);
  const twin = execFileSync("python3", ["-c", naivePy, resolve(FIX, "crosswalk-v2.7-c7dba29f.json")]);
  const naive = Buffer.from(naiveCanonicalText(JSON.parse(raw.toString("utf8"))), "utf8");
  assert.ok(naive.equals(twin), "naive Node and naive Python agree (no floats in this file)");
  assert.ok(src.equals(naive), "with no floats, the strict source form equals the naive form byte for byte");
  assert.ok(src.length < raw.length && src.length > 50000, `compact form is ${src.length} bytes of ${raw.length}`);
});

test("G0 value domain refusals, each by name", () => {
  const cases = [
    [{ x: 1.5 }, "G0_VALUE_FLOAT"], [{ x: 2 ** 53 }, "G0_VALUE_UNSAFE_INT"], [{ x: NaN }, "G0_VALUE_NON_FINITE"],
    [{ x: Infinity }, "G0_VALUE_NON_FINITE"], [{ x: "\uD800" }, "G0_STRING_LONE_SURROGATE"], [{ x: "a" + CTRL + "b" }, "G0_STRING_CONTROL"],
    [{ x: "a" + DEL + "b" }, "G0_STRING_DEL"], [{ "clé": 1 }, "G0_KEY_GRAMMAR"], [{ "$x": 1 }, "G0_KEY_GRAMMAR"], [{ "a-b": 1 }, "G0_KEY_GRAMMAR"],
    [{ x: undefined }, "G0_VALUE_UNDEFINED"], [{ x: new Map() }, "G0_VALUE_NON_PLAIN"], [{ x: new Date(0) }, "G0_VALUE_NON_PLAIN"],
    [{ x: 10n }, "G0_VALUE_BIGINT"], [{ x: () => 1 }, "G0_VALUE_TYPE"], [[1, [2, [1.25]]], "G0_VALUE_FLOAT"],
  ];
  for (const [v, code] of cases) {
    let err = null; try { assertG0Value(v); } catch (e) { err = e; }
    assert.ok(err, `${code}: nothing thrown`); assert.equal(err.code, code, `${code}: got ${err.message}`);
  }
  assertG0Value({ x: -0 }); assertG0Value({ x: 2 ** 53 - 1 }); assertG0Value({ x: "tab\tnl\ncr\r" }); assertG0Value({ [DECIMAL_KEY]: "1.0" });
  assertG0Value({ ok: { [DECIMAL_KEY]: "9007199254740992" } });
});

test("set-valued fields sort by canonical bytes and refuse duplicates", () => {
  const sorted = sortSet([{ b: 1 }, "z", "a", 10, 9, [1, 2], { a: 2 }]);
  assert.deepEqual(sorted.map((x) => canonicalTextG0(x)), ["\"a\"", "\"z\"", "10", "9", "[1,2]", "{\"a\":2}", "{\"b\":1}"]);
  assert.throws(() => sortSet([{ a: 1, b: 2 }, { b: 2, a: 1 }]), /G0_SET_DUPLICATE/);
  assert.throws(() => sortSet("nope"), /G0_SET_NOT_ARRAY/);
  assert.deepEqual(sortSet(["b", "a", "c"]), sortSet(["c", "a", "b"]));
});

test("hashRecord strips witness fields and is stable under key order", () => {
  const r1 = { lid: "claim:crosswalk:E-01", kind: "CLAIM", attrs: { a: 1 }, observed_at: "2026-09-02T00:00:00Z", host: "box" };
  const r2 = { host: "elsewhere", attrs: { a: 1 }, kind: "CLAIM", lid: "claim:crosswalk:E-01", observed_at: "2027-01-01T00:00:00Z" };
  const h1 = hashRecord(r1, { witness_fields: ["observed_at", "host"] });
  const h2 = hashRecord(r2, { witness_fields: ["observed_at", "host"] });
  assert.equal(h1.hash, h2.hash);
  assert.match(h1.hash, /^sha256:[0-9a-f]{64}$/);
  assert.equal(h1.bytes.toString("utf8"), '{"attrs":{"a":1},"kind":"CLAIM","lid":"claim:crosswalk:E-01"}');
  assert.notEqual(hashRecord({ ...r1, attrs: { a: 2 } }, { witness_fields: ["observed_at", "host"] }).hash, h1.hash);
});

test("leaf hash and CAS root have the documented shapes, and the twin's root formula is pinned here", () => {
  const bytes = canonicalBytesG0({ kind: "graphonomous.projection", entries: [] });
  assert.match(leafHashHex(bytes), /^[0-9a-f]{64}$/);
  assert.notEqual(leafHashHex(bytes), hashOfBytes(bytes).slice(7), "the 0x00 leaf prefix must change the digest");
  const root = artifactRoot({ kind: "graphonomous.projection", entries: [] });
  assert.match(root, /^root-[0-9a-f]{64}$/);
  const manual = "root-" + createHash("sha256").update(Buffer.concat([Buffer.from("TRVM-ARTIFACT-ROOT-v2|", "utf8"), bytes])).digest("hex");
  assert.equal(root, manual);
});
