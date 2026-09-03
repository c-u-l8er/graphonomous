/* schema.mjs — a small JSON Schema 2020-12 validator for the keywords the G0 record schemas use (R2 §7: shape errors
 * with JSON-Pointer locations). Zero dependencies (D-010). Supported: $ref (same document, `#/$defs/...`), $defs,
 * type (string | array), properties, required, additionalProperties (bool | schema), enum, const, pattern,
 * minLength, maxLength, minimum, maximum, items, prefixItems, minItems, maxItems, uniqueItems, anyOf, oneOf, allOf,
 * not, propertyNames, and two G0 annotations: `x-g0-set` (the array must be sorted by canonical bytes with no
 * duplicates) and `x-g0-witness` (the record type's witness fields, read by hashRecord). Anything else is refused at
 * schema load so a keyword this validator ignores can never look enforced. */
import { canonicalBytesG0, sortSet, G0Error } from "./canon.mjs";

const KNOWN = new Set(["$schema", "$id", "$ref", "$defs", "$comment", "title", "description", "type", "properties", "required",
  "additionalProperties", "enum", "const", "pattern", "minLength", "maxLength", "minimum", "maximum", "items", "prefixItems",
  "minItems", "maxItems", "minProperties", "maxProperties", "uniqueItems", "anyOf", "oneOf", "allOf", "not", "propertyNames", "x-g0-set", "x-g0-witness", "examples", "default"]);

export class SchemaError extends Error { constructor(msg) { super(msg); } }

function checkKeywords(schema, path = "#") {
  if (typeof schema === "boolean") return;
  for (const k of Object.keys(schema)) if (!KNOWN.has(k)) throw new SchemaError(`unsupported keyword ${k} at ${path} — this validator would ignore it`);
  for (const k of ["properties", "$defs"]) if (schema[k]) for (const [n, s] of Object.entries(schema[k])) checkKeywords(s, `${path}/${k}/${n}`);
  for (const k of ["items", "not", "propertyNames"]) if (schema[k] !== undefined && typeof schema[k] === "object") checkKeywords(schema[k], `${path}/${k}`);
  if (typeof schema.additionalProperties === "object") checkKeywords(schema.additionalProperties, `${path}/additionalProperties`);
  for (const k of ["anyOf", "oneOf", "allOf", "prefixItems"]) if (schema[k]) schema[k].forEach((s, i) => checkKeywords(s, `${path}/${k}/${i}`));
}

export function compile(root) {
  checkKeywords(root);
  const resolveRef = (ref) => {
    if (!ref.startsWith("#/")) throw new SchemaError(`only same-document refs are supported: ${ref}`);
    let cur = root;
    for (const seg of ref.slice(2).split("/")) { cur = cur?.[seg.replace(/~1/g, "/").replace(/~0/g, "~")]; if (cur === undefined) throw new SchemaError(`unresolved $ref ${ref}`); }
    return cur;
  };
  const typeOf = (v) => v === null ? "null" : Array.isArray(v) ? "array" : typeof v === "number" ? (Number.isInteger(v) ? "integer" : "number") : typeof v;
  const matchesType = (v, t) => t === "number" ? typeof v === "number" : t === "integer" ? Number.isInteger(v) : typeOf(v) === t;
  function validate(schema, v, ip, sp, errors) {
    if (schema === true) return; if (schema === false) { errors.push({ instancePath: ip, schemaPath: sp, keyword: "false", message: "schema is false" }); return; }
    if (schema.$ref) { validate(resolveRef(schema.$ref), v, ip, schema.$ref, errors); }
    if (schema.type !== undefined) { const ts = Array.isArray(schema.type) ? schema.type : [schema.type]; if (!ts.some((t) => matchesType(v, t))) { errors.push({ instancePath: ip, schemaPath: sp + "/type", keyword: "type", message: `expected ${ts.join("|")}, got ${typeOf(v)}` }); return; } }
    if (schema.const !== undefined && canonicalBytesG0(v).toString("utf8") !== canonicalBytesG0(schema.const).toString("utf8")) errors.push({ instancePath: ip, schemaPath: sp + "/const", keyword: "const", message: `must equal ${JSON.stringify(schema.const)}` });
    if (schema.enum && !schema.enum.some((e) => canonicalBytesG0(e).toString("utf8") === canonicalBytesG0(v).toString("utf8"))) errors.push({ instancePath: ip, schemaPath: sp + "/enum", keyword: "enum", message: `${JSON.stringify(v).slice(0, 60)} not in enum` });
    if (typeof v === "string") {
      if (schema.pattern && !new RegExp(schema.pattern, "u").test(v)) errors.push({ instancePath: ip, schemaPath: sp + "/pattern", keyword: "pattern", message: `does not match ${schema.pattern}` });
      if (schema.minLength !== undefined && [...v].length < schema.minLength) errors.push({ instancePath: ip, schemaPath: sp + "/minLength", keyword: "minLength", message: `shorter than ${schema.minLength}` });
      if (schema.maxLength !== undefined && [...v].length > schema.maxLength) errors.push({ instancePath: ip, schemaPath: sp + "/maxLength", keyword: "maxLength", message: `longer than ${schema.maxLength}` });
    }
    if (typeof v === "number") {
      if (schema.minimum !== undefined && v < schema.minimum) errors.push({ instancePath: ip, schemaPath: sp + "/minimum", keyword: "minimum", message: `${v} < ${schema.minimum}` });
      if (schema.maximum !== undefined && v > schema.maximum) errors.push({ instancePath: ip, schemaPath: sp + "/maximum", keyword: "maximum", message: `${v} > ${schema.maximum}` });
    }
    if (Array.isArray(v)) {
      if (schema.minItems !== undefined && v.length < schema.minItems) errors.push({ instancePath: ip, schemaPath: sp + "/minItems", keyword: "minItems", message: `fewer than ${schema.minItems} items` });
      if (schema.maxItems !== undefined && v.length > schema.maxItems) errors.push({ instancePath: ip, schemaPath: sp + "/maxItems", keyword: "maxItems", message: `more than ${schema.maxItems} items` });
      if (schema.prefixItems) schema.prefixItems.forEach((s, i) => { if (i < v.length) validate(s, v[i], `${ip}/${i}`, `${sp}/prefixItems/${i}`, errors); });
      if (schema.items !== undefined) v.forEach((x, i) => { if (!schema.prefixItems || i >= schema.prefixItems.length) validate(schema.items, x, `${ip}/${i}`, `${sp}/items`, errors); });
      if (schema.uniqueItems || schema["x-g0-set"]) {
        const seen = new Set(); for (const x of v) { const b = canonicalBytesG0(x).toString("utf8"); if (seen.has(b)) { errors.push({ instancePath: ip, schemaPath: sp + "/uniqueItems", keyword: "uniqueItems", message: `duplicate item ${b.slice(0, 60)}` }); break; } seen.add(b); }
      }
      if (schema["x-g0-set"]) {
        try { const s = sortSet(v); if (JSON.stringify(s.map((x) => canonicalBytesG0(x).toString("utf8"))) !== JSON.stringify(v.map((x) => canonicalBytesG0(x).toString("utf8")))) errors.push({ instancePath: ip, schemaPath: sp + "/x-g0-set", keyword: "x-g0-set", message: "set is not sorted by canonical bytes" }); }
        catch (e) { errors.push({ instancePath: ip, schemaPath: sp + "/x-g0-set", keyword: "x-g0-set", message: e.message }); }
      }
    }
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const props = schema.properties || {};
      const nk = Object.keys(v).length;
      if (schema.minProperties !== undefined && nk < schema.minProperties) errors.push({ instancePath: ip, schemaPath: sp + "/minProperties", keyword: "minProperties", message: `fewer than ${schema.minProperties} properties` });
      if (schema.maxProperties !== undefined && nk > schema.maxProperties) errors.push({ instancePath: ip, schemaPath: sp + "/maxProperties", keyword: "maxProperties", message: `more than ${schema.maxProperties} properties` });
      for (const r of schema.required || []) if (!(r in v)) errors.push({ instancePath: ip, schemaPath: sp + "/required", keyword: "required", message: `missing ${r}` });
      for (const [k, x] of Object.entries(v)) {
        if (schema.propertyNames) validate(schema.propertyNames, k, `${ip}/${k}`, sp + "/propertyNames", errors);
        if (k in props) validate(props[k], x, `${ip}/${k}`, `${sp}/properties/${k}`, errors);
        else if (schema.additionalProperties === false) errors.push({ instancePath: `${ip}/${k}`, schemaPath: sp + "/additionalProperties", keyword: "additionalProperties", message: `unexpected field ${k}` });
        else if (schema.additionalProperties && typeof schema.additionalProperties === "object") validate(schema.additionalProperties, x, `${ip}/${k}`, sp + "/additionalProperties", errors);
      }
    }
    if (schema.allOf) schema.allOf.forEach((s, i) => validate(s, v, ip, `${sp}/allOf/${i}`, errors));
    if (schema.anyOf) { const ok = schema.anyOf.some((s) => { const e = []; validate(s, v, ip, sp, e); return e.length === 0; }); if (!ok) errors.push({ instancePath: ip, schemaPath: sp + "/anyOf", keyword: "anyOf", message: "matches none of anyOf" }); }
    if (schema.oneOf) { const n = schema.oneOf.filter((s) => { const e = []; validate(s, v, ip, sp, e); return e.length === 0; }).length; if (n !== 1) errors.push({ instancePath: ip, schemaPath: sp + "/oneOf", keyword: "oneOf", message: `matches ${n} of oneOf, need exactly 1` }); }
    if (schema.not) { const e = []; validate(schema.not, v, ip, sp, e); if (e.length === 0) errors.push({ instancePath: ip, schemaPath: sp + "/not", keyword: "not", message: "matches a forbidden schema" }); }
  }
  const fn = (v) => { const errors = []; try { validate(root, v, "", "#", errors); } catch (e) { if (e instanceof G0Error) errors.push({ instancePath: "", schemaPath: "#", keyword: "g0-domain", message: e.message }); else throw e; } return errors; };
  fn.witnessFields = root["x-g0-witness"] || [];
  fn.schema = root;
  return fn;
}
