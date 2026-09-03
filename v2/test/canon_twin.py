#!/usr/bin/env python3
"""canon_twin.py — the independent Python conformance twin of lib/canon.mjs (spec §6.3, D-010).

It shares no code with the Node side. It reads SOURCE JSON text with the same rules (integer lexemes within ±(2^53−1)
stay integers; every other numeric lexeme becomes {"decimal_string": lexeme}; duplicate keys, lone surrogates and raw
control characters are refused), applies the same G0 value-domain guard, and emits canonical UTF-8 bytes with
json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False). Under the G0 domain those
bytes must equal TRVM `canonicalBytes` on the Node side, byte for byte — the test compares files, not hashes.

    python3 canon_twin.py --vectors <vectors.json> --out <dir>      writes <dir>/<name>.canon (or .refused)
    python3 canon_twin.py --file <source.json> --out <dir> [--naive] writes <dir>/<basename>.canon (+ .naive.canon)
    python3 canon_twin.py --manifest <projection dir>               recomputes record hashes and the CAS root
    python3 canon_twin.py --selftest
"""
import argparse, hashlib, json, os, re, sys

MAX_SAFE = 9007199254740991
KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SOURCE_KEY_RE = re.compile(r"^[\x20-\x7e]+$")
NUMBER_LEXEME_RE = re.compile(r"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$")
DECIMAL_KEY = "decimal_string"
CAS_TAG = b"TRVM-ARTIFACT-ROOT-v2|"


class Refusal(Exception):
    def __init__(self, code, msg):
        super().__init__(f"{code}: {msg}")
        self.code = code


# ── strict source reader ────────────────────────────────────────────────────────────────────────
def _parse_int(lex):
    v = int(lex)
    if -MAX_SAFE <= v <= MAX_SAFE:
        return v
    return {DECIMAL_KEY: lex}


def _parse_float(lex):
    return {DECIMAL_KEY: lex}


def _parse_constant(name):
    raise Refusal("MALFORMED", f"non-JSON literal {name}")


def _pairs_hook(pairs):
    seen = set()
    out = {}
    for k, v in pairs:
        if k in seen:
            raise Refusal("DUPLICATE_KEY", f"duplicate member {k!r}")
        seen.add(k)
        out[k] = v
    return out


def _check_surrogates(v, path=""):
    if isinstance(v, str):
        for ch in v:
            o = ord(ch)
            if 0xD800 <= o <= 0xDFFF:
                raise Refusal("LONE_SURROGATE", f"lone surrogate in {path or '/'}")
    elif isinstance(v, dict):
        for k, x in v.items():
            _check_surrogates(k, path + "/<key>")
            _check_surrogates(x, path + "/" + k)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            _check_surrogates(x, f"{path}/{i}")


def parse_strict(data):
    """data: bytes or str. Returns the parsed value with D-026 number handling."""
    if isinstance(data, (bytes, bytearray)):
        try:
            text = bytes(data).decode("utf-8")  # strict: raises on invalid UTF-8
        except UnicodeDecodeError as e:
            raise Refusal("INVALID_UTF8", str(e))
    else:
        text = data
    try:
        v = json.loads(text, parse_int=_parse_int, parse_float=_parse_float, parse_constant=_parse_constant,
                       object_pairs_hook=_pairs_hook, strict=True)
    except Refusal:
        raise
    except json.JSONDecodeError as e:
        msg = e.msg
        if "control character" in msg:
            raise Refusal("CONTROL_IN_STRING", msg)
        raise Refusal("MALFORMED", msg)
    except ValueError as e:  # e.g. int() of an odd lexeme
        raise Refusal("MALFORMED", str(e))
    _check_surrogates(v)  # Python's json decodes \ud800 to a lone surrogate without complaint
    return v


# ── the G0 value domain ─────────────────────────────────────────────────────────────────────────
def is_decimal_string(v):
    return isinstance(v, dict) and len(v) == 1 and isinstance(v.get(DECIMAL_KEY), str) and bool(NUMBER_LEXEME_RE.match(v[DECIMAL_KEY]))


def assert_g0_value(v, path="", keys="record"):
    key_re = SOURCE_KEY_RE if keys == "source" else KEY_RE
    key_code = "G0_KEY_NON_ASCII" if keys == "source" else "G0_KEY_GRAMMAR"
    if v is None or isinstance(v, bool):
        return
    if isinstance(v, int):
        if abs(v) > MAX_SAFE:
            raise Refusal("G0_VALUE_UNSAFE_INT", f"integer {v} at {path or '/'}")
        return
    if isinstance(v, float):
        raise Refusal("G0_VALUE_FLOAT", f"float at {path or '/'}")
    if isinstance(v, str):
        for ch in v:
            o = ord(ch)
            if o < 0x20 and o not in (9, 10, 13):
                raise Refusal("G0_STRING_CONTROL", f"U+{o:04x} at {path or '/'}")
            if o == 0x7F:
                raise Refusal("G0_STRING_DEL", f"U+007F at {path or '/'}")
            if 0xD800 <= o <= 0xDFFF:
                raise Refusal("G0_STRING_LONE_SURROGATE", f"lone surrogate at {path or '/'}")
        return
    if isinstance(v, list):
        for i, x in enumerate(v):
            assert_g0_value(x, f"{path}/{i}", keys)
        return
    if isinstance(v, dict):
        if is_decimal_string(v):
            return
        for k, x in v.items():
            if not key_re.match(k):
                raise Refusal(key_code, f"key {k!r} at {path or '/'}")
            assert_g0_value(x, f"{path}/{k}", keys)
        return
    raise Refusal("G0_VALUE_TYPE", f"{type(v).__name__} at {path or '/'}")


def canonical_bytes_g0(v, keys="record"):
    assert_g0_value(v, "", keys)
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


def naive_canonical_bytes(v):
    """The naive discipline (json.loads + json.dumps) — used only to REPRODUCE the divergence, never by an adapter."""
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def cas_root(canonical_bytes):
    return "root-" + hashlib.sha256(CAS_TAG + canonical_bytes).hexdigest()


def leaf_hex(canonical_bytes):
    return hashlib.sha256(b"\x00" + canonical_bytes).hexdigest()


# ── commands ────────────────────────────────────────────────────────────────────────────────────
def run_vectors(path, out):
    d = json.load(open(path, encoding="utf-8"))
    os.makedirs(out, exist_ok=True)
    report = []
    for vec in d["vectors"]:
        if not vec.get("twin"):
            continue
        name = vec["name"]
        try:
            v = parse_strict(vec["text"])
            b = canonical_bytes_g0(v)
            open(os.path.join(out, name + ".canon"), "wb").write(b)
            report.append({"name": name, "accept": True, "sha256": sha256_hex(b), "bytes": len(b)})
        except Refusal as e:
            open(os.path.join(out, name + ".refused"), "w").write(e.code + "\n")
            report.append({"name": name, "accept": False, "refusal": e.code})
    json.dump(report, open(os.path.join(out, "vectors.report.json"), "w"), indent=1)
    return report


def run_file(path, out, naive=False):
    raw = open(path, "rb").read()
    os.makedirs(out, exist_ok=True)
    base = os.path.basename(path)
    v = parse_strict(raw)
    b = canonical_bytes_g0(v, keys="source")  # a SOURCE file keeps its own keys (printable ASCII); records use the identifier grammar
    open(os.path.join(out, base + ".canon"), "wb").write(b)
    rep = {"file": base, "g0_sha256": sha256_hex(b), "g0_bytes": len(b)}
    if naive:
        nb = naive_canonical_bytes(json.loads(raw.decode("utf-8")))
        open(os.path.join(out, base + ".naive.canon"), "wb").write(nb)
        rep.update({"naive_sha256": sha256_hex(nb), "naive_bytes": len(nb)})
    json.dump(rep, open(os.path.join(out, base + ".report.json"), "w"), indent=1)
    return rep


def run_manifest(pdir):
    """Recompute every record hash listed in manifest.json from the canonical record files, and the CAS root of the
    manifest itself. Prints a JSON verdict; exit 1 on any disagreement."""
    man_path = os.path.join(pdir, "manifest.json")
    man_bytes = open(man_path, "rb").read()
    man = parse_strict(man_bytes)
    # the manifest file on disk must itself be canonical
    problems = []
    if canonical_bytes_g0(man) != man_bytes:
        problems.append("manifest.json is not in canonical form")
    # records: <kind>/<lid-hash>.json? No — records are in per-kind files; each entry is [lid, sha256:...] and the
    # record bytes are located through records_index.json (lid -> relative file + byte offsets) written by the projector.
    idx = {e["lid"]: e for e in parse_strict(open(os.path.join(pdir, "records_index.json"), "rb").read())}
    checked = 0
    for lid, want in man["entries"]:
        loc = idx.get(lid)
        if loc is None:
            problems.append(f"no index entry for {lid}")
            continue
        data = open(os.path.join(pdir, loc["file"]), "rb").read()
        line = data.split(b"\n")[loc["line"]]
        got = "sha256:" + sha256_hex(line)
        if got != want:
            problems.append(f"{lid}: manifest says {want}, bytes hash to {got}")
        # and the line must be canonical for its own parse
        if canonical_bytes_g0(parse_strict(line)) != line:
            problems.append(f"{lid}: stored line is not canonical")
        checked += 1
    root = cas_root(man_bytes)
    root_file = open(os.path.join(pdir, "ROOT"), encoding="utf-8").read().strip() if os.path.exists(os.path.join(pdir, "ROOT")) else None
    if root_file and root_file != root:
        problems.append(f"ROOT file says {root_file}, twin computes {root}")
    verdict = {"checked": checked, "entries": len(man["entries"]), "root_twin": root, "root_file": root_file, "problems": problems}
    print(json.dumps(verdict, indent=1))
    return 0 if not problems else 1


def selftest():
    assert parse_strict('{"a": 1.0}') == {"a": {DECIMAL_KEY: "1.0"}}
    assert canonical_bytes_g0(parse_strict('{"b":1,"a":[3,{"z":true,"y":null}],"c":"x"}')) == b'{"a":[3,{"y":null,"z":true}],"b":1,"c":"x"}'
    assert canonical_bytes_g0(parse_strict('{"x": -0}')) == b'{"x":0}'
    for text, code in [('{"a":1,"a":2}', "DUPLICATE_KEY"), ('{"s":"\\ud800"}', "LONE_SURROGATE"), ('{"x": NaN}', "MALFORMED"), ('{"clé":1}', "G0_KEY_GRAMMAR")]:
        try:
            canonical_bytes_g0(parse_strict(text))
            raise SystemExit(f"selftest: {text} was accepted")
        except Refusal as e:
            assert e.code == code, (text, e.code, code)
    try:
        canonical_bytes_g0({"x": 1.5})
        raise SystemExit("selftest: float accepted")
    except Refusal as e:
        assert e.code == "G0_VALUE_FLOAT"
    print("canon_twin selftest: ok")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vectors"); ap.add_argument("--file"); ap.add_argument("--out"); ap.add_argument("--naive", action="store_true")
    ap.add_argument("--manifest"); ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.vectors:
        rep = run_vectors(a.vectors, a.out or ".twin-out"); print(json.dumps(rep)); return 0
    if a.file:
        rep = run_file(a.file, a.out or ".twin-out", a.naive); print(json.dumps(rep)); return 0
    if a.manifest:
        return run_manifest(a.manifest)
    ap.print_help(); return 2


if __name__ == "__main__":
    sys.exit(main())
