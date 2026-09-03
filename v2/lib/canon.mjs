/* canon.mjs — G0 canonical bytes, the strict source reader, and the identity hashes.
 *
 * ONE ENCODER. The canonical form is TRVM `canonicalBytes` (RFC 8785-measured), imported from the pinned sibling
 * checkout — never a fourth implementation (D-006, spec §6.3). What this module adds is the G0 VALUE DOMAIN
 * (spec §6.2, R2 rules 1–10): under it TRVM's, WRL's and Python's serializers agree byte for byte; outside it they
 * do not, and one real registry file already proved it (TEST_FIXTURES/canon-divergence-2026-09-02.md).
 *
 * TWO READERS, ONE RULE. `JSON.parse` loses the lexeme: the JSON text `1.0` becomes the number 1 in JS and the float
 * 1.0 in Python, and the two then canonicalize differently. `parseStrictJson` keeps the lexeme, turns every
 * non-integer or unsafe number into `{"decimal_string": "<lexeme>"}` (D-026) and refuses duplicate keys, which
 * `JSON.parse` silently resolves last-wins (the CAS header records why that is a cross-implementation hazard).
 *
 * WHAT IS NEVER HASHED. Witness fields (timestamps, hosts, run ids) are stripped by `hashRecord`; a record type
 * declares them (R2 rule 8). The hash string form is `sha256:<64 hex>`; the projection root is a TRVM CAS `root-`.
 */
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { canonicalBytes as trvmCanonicalBytes, canonicalString } from "../../../TRVM/governance/derive_protocol.mjs";
import { artifactRoot, canonicalWireBytes, rootOfBytes, ARTIFACT_ROOT_PROTOCOL } from "../../../TRVM/governance/cas.mjs";

export { trvmCanonicalBytes, artifactRoot, rootOfBytes, ARTIFACT_ROOT_PROTOCOL };

const HERE = dirname(fileURLToPath(import.meta.url));
export const TRVM_DIR = resolve(HERE, "../../../TRVM");

/** The TRVM revision this module was written against (spec §14 pins). A moved blob is a refusal, not a warning:
 *  a canonicalizer that changed under us would move every identity G0 has ever minted. */
export const TRVM_PIN = Object.freeze({
  commit: "8816e59055322fc608c9bc7dae9723c02d8402b7",
  branch: "merge/governance-plane",
  blobs: Object.freeze({
    "governance/derive_protocol.mjs": "8ec73d9b3401e1e013388c6daf9d8b2c63d43954",
    "governance/cas.mjs": "4b84dff4b4d1fd68412c579cd9683b8dc4075d7f",
    "governance/observed_execution_host.mjs": "29df27f703021baa5cccc9bb24acea52c31c1873",
    // G0-D (lib/certificate.mjs): the certificate identity and the checker grammar/ownership/result helpers. ONE pin
    // constant on purpose — TRVM-P0 lands as a new TRVM commit; re-pin here and re-mint the certificates (G0D_GOLDEN_VECTORS).
    // TRVM-P0.1 (8816e59) is the sharpest case of that discipline so far: it moved the COMMIT and not ONE of these five
    // blobs, so `assertTrvmPinned` — which reads blobs — would never have noticed, and every certificate would have gone
    // on naming a commit that no longer describes the checker's normative release (spec revision 1 → 2, 28 refusal codes
    // → 30). The commit is in the chain precisely so that a change to the OWNING LAYER's release is visible here even
    // when the imported bytes are identical. Re-pinned, and the three TRVM-P0 certificates are preserved under
    // projections/pre-trvmp01/ as receipts that verify under their pinned verifier coordinates (D-060).
    "governance/certificate.mjs": "2ee734896519e1d9e7a50f4fbda92c74c9c032d3",
    "governance/schema.mjs": "4b821c2889bfa3c01d9ccb4b05e66817bb3bc0ed",
  }),
});

/** git's blob id without invoking git: sha1("blob <len>\0" ++ bytes) — this repository is SHA-1. */
export const gitBlobOid = (bytes) =>
  createHash("sha1").update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`, "utf8"), bytes])).digest("hex");

/** Refuses to run if the imported TRVM files are not the pinned blobs. Returns the verified table. */
export function assertTrvmPinned() {
  const seen = {};
  for (const [rel, want] of Object.entries(TRVM_PIN.blobs)) {
    const got = gitBlobOid(readFileSync(resolve(TRVM_DIR, rel)));
    seen[rel] = got;
    if (got !== want) throw new G0Error("TRVM_MOVED", `${rel} is blob ${got}, pinned ${want} (commit ${TRVM_PIN.commit})`);
  }
  return seen;
}

/* ─────────────────────────────────────────── errors ─────────────────────────────────────────── */
export class G0Error extends Error {
  constructor(code, message, extra = {}) { super(`${code}: ${message}`); this.code = code; Object.assign(this, extra); }
}

/* ────────────────────────────────────── the value domain ────────────────────────────────────── */
export const MAX_SAFE = 9007199254740991; // 2^53 − 1 (R2 rule 2)
export const KEY_RE = /^[A-Za-z_][A-Za-z0-9_]*$/; // R2 rule 4: ASCII keys, so code-point, byte and UTF-16 orders coincide
export const INT_LEXEME_RE = /^-?(0|[1-9][0-9]*)$/;
export const NUMBER_LEXEME_RE = /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/;
export const DECIMAL_KEY = "decimal_string";

/** Is `v` the D-026 wrapper for a non-integer / unsafe source number? */
export const isDecimalString = (v) =>
  v !== null && typeof v === "object" && !Array.isArray(v) &&
  Object.keys(v).length === 1 && typeof v[DECIMAL_KEY] === "string" && NUMBER_LEXEME_RE.test(v[DECIMAL_KEY]);

export const SOURCE_KEY_RE = /^[\x20-\x7e]+$/; // printable ASCII: source objects keep their own keys, but a non-ASCII key would sort differently across runtimes

/** Validate a value against spec §6.2. `keys: "record"` (default) enforces the identifier grammar normalized records
 *  use; `keys: "source"` accepts any printable-ASCII key so a SOURCE object (whose keys we do not control) can be
 *  canonicalized for comparison — never hashed as a record. Throws G0Error with a JSON-pointer-ish path. */
export function assertG0Value(v, path = "", opts = {}) {
  const keyRe = opts.keys === "source" ? SOURCE_KEY_RE : KEY_RE;
  const keyCode = opts.keys === "source" ? "G0_KEY_NON_ASCII" : "G0_KEY_GRAMMAR";
  if (v === null || typeof v === "boolean") return;
  const t = typeof v;
  if (t === "number") {
    if (!Number.isFinite(v)) throw new G0Error("G0_VALUE_NON_FINITE", `non-finite number at ${path || "/"}`);
    if (!Number.isInteger(v)) throw new G0Error("G0_VALUE_FLOAT", `non-integer number ${v} at ${path || "/"} — carry it as {"${DECIMAL_KEY}": "<lexeme>"}`);
    if (Math.abs(v) > MAX_SAFE) throw new G0Error("G0_VALUE_UNSAFE_INT", `integer ${v} outside ±(2^53−1) at ${path || "/"}`);
    if (Object.is(v, -0)) return; // canonicalizes to 0 in every runtime (measured); allowed
    return;
  }
  if (t === "string") { assertG0String(v, path); return; }
  if (t === "bigint") throw new G0Error("G0_VALUE_BIGINT", `bigint at ${path || "/"} — carry it as a decimal string`);
  if (t !== "object") throw new G0Error("G0_VALUE_TYPE", `${t} at ${path || "/"}`);
  if (Array.isArray(v)) { v.forEach((x, i) => assertG0Value(x, `${path}/${i}`, opts)); return; }
  const proto = Object.getPrototypeOf(v);
  if (proto !== Object.prototype && proto !== null)
    throw new G0Error("G0_VALUE_NON_PLAIN", `${v.constructor?.name ?? "object"} at ${path || "/"}`);
  if (isDecimalString(v)) return;
  for (const k of Object.keys(v)) {
    if (!keyRe.test(k)) throw new G0Error(keyCode, `key ${JSON.stringify(k)} at ${path || "/"} is not ${keyRe}`);
    if (v[k] === undefined) throw new G0Error("G0_VALUE_UNDEFINED", `undefined at ${path}/${k} — omit absent fields`);
    assertG0Value(v[k], `${path}/${k}`, opts);
  }
}

/** R2 rule 5: well-formed scalar values, no C0 control except \t \n \r, no U+007F. Lone surrogates are caught by
 *  TRVM's `canonicalString` too; we check first so the refusal is named. */
export function assertG0String(s, path = "") {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x20 && c !== 0x09 && c !== 0x0a && c !== 0x0d)
      throw new G0Error("G0_STRING_CONTROL", `U+${c.toString(16).padStart(4, "0")} in string at ${path || "/"}`);
    if (c === 0x7f) throw new G0Error("G0_STRING_DEL", `U+007F in string at ${path || "/"}`);
    if (c >= 0xd800 && c <= 0xdbff) {
      const n = s.charCodeAt(i + 1);
      if (!(n >= 0xdc00 && n <= 0xdfff)) throw new G0Error("G0_STRING_LONE_SURROGATE", `lone high surrogate at ${path || "/"}`);
      i++;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      throw new G0Error("G0_STRING_LONE_SURROGATE", `lone low surrogate at ${path || "/"}`);
    }
  }
}

/* ─────────────────────────────────────── canonical bytes ────────────────────────────────────── */
/** Canonical UTF-8 bytes of a NORMALIZED value: the G0 domain guard, then TRVM's encoder. Returns a Buffer. */
export function canonicalBytesG0(v) {
  assertG0Value(v);
  return canonicalWireBytes(v); // Buffer.from(trvmCanonicalBytes(v), "utf8") — the CAS wire form
}
export const canonicalTextG0 = (v) => canonicalBytesG0(v).toString("utf8");
/** Canonical UTF-8 bytes of a SOURCE value (keys as found, printable ASCII): the value-domain guard without the record
 *  key grammar. For measurements and cross-runtime comparison of source files; adapters hash records, not sources. */
export function canonicalBytesSource(v) { assertG0Value(v, "", { keys: "source" }); return canonicalWireBytes(v); }

export const sha256Hex = (bytes) => createHash("sha256").update(bytes).digest("hex");
/** The record hash string form (R2 rule 14). */
export const hashOfBytes = (bytes) => "sha256:" + sha256Hex(bytes);
/** RFC 9162 leaf: sha256(0x00 ‖ bytes), hex (R2 rule 15) — so a Merkle tree can be layered later without re-hashing. */
export const leafHashHex = (bytes) => createHash("sha256").update(Buffer.concat([Buffer.from([0]), bytes])).digest("hex");

/** Hash a record with its witness fields removed (R2 rule 8). Returns {hash, bytes, identity}. */
export function hashRecord(record, { witness_fields = [] } = {}) {
  const identity = {};
  for (const k of Object.keys(record)) if (!witness_fields.includes(k)) identity[k] = record[k];
  const bytes = canonicalBytesG0(identity);
  return { hash: hashOfBytes(bytes), bytes, identity };
}

/** Byte-order comparison of canonical forms (R3 §3 rule 2: UTF-8 bytes, identical across languages). */
export const compareCanonical = (a, b) => Buffer.compare(canonicalBytesG0(a), canonicalBytesG0(b));

/** A set-valued field: sorted by canonical bytes, duplicates refused (R2 rule 6). Returns a new array. */
export function sortSet(arr, path = "") {
  if (!Array.isArray(arr)) throw new G0Error("G0_SET_NOT_ARRAY", `set field at ${path || "/"} is not an array`);
  const keyed = arr.map((x, i) => ({ x, b: canonicalBytesG0(x), i }));
  keyed.sort((p, q) => Buffer.compare(p.b, q.b));
  for (let i = 1; i < keyed.length; i++)
    if (keyed[i].b.equals(keyed[i - 1].b))
      throw new G0Error("G0_SET_DUPLICATE", `duplicate member ${keyed[i].b.toString("utf8").slice(0, 80)} in set at ${path || "/"}`);
  return keyed.map((k) => k.x);
}

/* ────────────────────────────────── the strict source reader ────────────────────────────────── */
/** Parse SOURCE JSON text strictly, preserving what `JSON.parse` loses.
 *  - integer lexemes within ±(2^53−1) → Number; every other numeric lexeme → {decimal_string: lexeme} (D-026);
 *  - duplicate member names → G0Error DUPLICATE_KEY (JSON.parse keeps the last; I-JSON forbids them);
 *  - lone surrogates (even as \uD800 escapes) → G0Error LONE_SURROGATE (RFC 8785 terminates canonicalisation);
 *  - raw control characters in strings → G0Error CONTROL_IN_STRING (RFC 8259 forbids them);
 *  - NaN/Infinity/trailing garbage/comments → G0Error MALFORMED.
 *  Returns {value, number_forms: [{pointer, lexeme}], bytes}. `text` may be a Buffer (decoded as fatal UTF-8). */
export function parseStrictJson(text, { max_depth = 512 } = {}) {
  let s;
  if (Buffer.isBuffer(text) || text instanceof Uint8Array) {
    try { s = new TextDecoder("utf-8", { fatal: true }).decode(text); }
    catch (e) { throw new G0Error("INVALID_UTF8", String(e?.message ?? e)); }
  } else s = String(text);
  let i = 0; const n = s.length; const number_forms = [];
  const fail = (code, msg) => { throw new G0Error(code, `${msg} at offset ${i}`); };
  const ws = () => { while (i < n) { const c = s.charCodeAt(i); if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d) i++; else break; } };
  const escapePointer = (k) => k.replace(/~/g, "~0").replace(/\//g, "~1");
  const parseValue = (pointer, depth) => {
    if (depth > max_depth) fail("MALFORMED", "nesting deeper than " + max_depth);
    ws(); if (i >= n) fail("MALFORMED", "unexpected end");
    const c = s[i];
    if (c === "{") return parseObject(pointer, depth);
    if (c === "[") return parseArray(pointer, depth);
    if (c === '"') return parseString(pointer);
    if (c === "t" && s.startsWith("true", i)) { i += 4; return true; }
    if (c === "f" && s.startsWith("false", i)) { i += 5; return false; }
    if (c === "n" && s.startsWith("null", i)) { i += 4; return null; }
    if (c === "-" || (c >= "0" && c <= "9")) return parseNumber(pointer);
    fail("MALFORMED", `unexpected ${JSON.stringify(c)}`);
  };
  const parseNumber = (pointer) => {
    const start = i;
    if (s[i] === "-") i++;
    while (i < n && /[0-9.eE+-]/.test(s[i])) i++;
    const lex = s.slice(start, i);
    if (!NUMBER_LEXEME_RE.test(lex)) fail("MALFORMED", `bad number lexeme ${JSON.stringify(lex)}`);
    if (INT_LEXEME_RE.test(lex)) {
      const big = BigInt(lex);
      if (big <= 9007199254740991n && big >= -9007199254740991n) return Number(big);
    }
    number_forms.push({ pointer, lexeme: lex });
    return { [DECIMAL_KEY]: lex };
  };
  const parseString = (pointer) => {
    i++; let out = "";
    for (;;) {
      if (i >= n) fail("MALFORMED", "unterminated string");
      const ch = s[i]; const code = s.charCodeAt(i);
      if (ch === '"') { i++; break; }
      if (code < 0x20) fail("CONTROL_IN_STRING", `raw U+${code.toString(16).padStart(4, "0")} in string ${pointer || "/"}`);
      if (ch === "\\") {
        const e = s[i + 1];
        if (e === "u") {
          const hex = s.slice(i + 2, i + 6);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) fail("MALFORMED", "bad \\u escape");
          out += String.fromCharCode(parseInt(hex, 16)); i += 6;
        } else {
          const map = { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t" };
          if (!(e in map)) fail("MALFORMED", `bad escape \\${e}`);
          out += map[e]; i += 2;
        }
      } else { out += ch; i++; }
    }
    // surrogate pairing over the DECODED string (an escaped \uD800 is as lone as a raw one)
    for (let j = 0; j < out.length; j++) {
      const c = out.charCodeAt(j);
      if (c >= 0xd800 && c <= 0xdbff) { const d = out.charCodeAt(j + 1); if (!(d >= 0xdc00 && d <= 0xdfff)) fail("LONE_SURROGATE", `lone high surrogate in ${pointer || "/"}`); j++; }
      else if (c >= 0xdc00 && c <= 0xdfff) fail("LONE_SURROGATE", `lone low surrogate in ${pointer || "/"}`);
    }
    return out;
  };
  const parseArray = (pointer, depth) => {
    i++; const arr = []; ws();
    if (s[i] === "]") { i++; return arr; }
    for (;;) { arr.push(parseValue(`${pointer}/${arr.length}`, depth + 1)); ws();
      if (s[i] === ",") { i++; continue; } if (s[i] === "]") { i++; return arr; } fail("MALFORMED", "expected , or ]"); }
  };
  const parseObject = (pointer, depth) => {
    i++; const obj = {}; const seen = new Set(); ws();
    if (s[i] === "}") { i++; return obj; }
    for (;;) {
      ws(); if (s[i] !== '"') fail("MALFORMED", "expected a member name");
      const k = parseString(pointer + "/<key>"); ws();
      if (s[i] !== ":") fail("MALFORMED", "expected :"); i++;
      if (seen.has(k)) fail("DUPLICATE_KEY", `duplicate member ${JSON.stringify(k)} in ${pointer || "/"}`);
      seen.add(k);
      obj[k] = parseValue(`${pointer}/${escapePointer(k)}`, depth + 1); ws();
      if (s[i] === ",") { i++; continue; } if (s[i] === "}") { i++; return obj; } fail("MALFORMED", "expected , or }");
    }
  };
  const value = parseValue("", 0); ws();
  if (i !== n) fail("MALFORMED", "trailing characters");
  return { value, number_forms, bytes: Buffer.isBuffer(text) ? text : Buffer.from(s, "utf8") };
}

/** Sorted-key canonical text of ANY parsed JSON value without the G0 guard — used only by tests to reproduce the
 *  naive discipline (and its divergence); never by an adapter. */
export const naiveCanonicalText = (v) => trvmCanonicalBytes(v);
