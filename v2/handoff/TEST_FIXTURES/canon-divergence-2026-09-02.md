# Fixture — canonical bytes across two languages (measured 2026-09-02)

**Question.** If G0 canonicalizes source JSON with the identity spine's discipline (sorted keys, compact separators,
UTF-8, scalars serialized natively), do Node and Python produce the same bytes over the real registries?

**Method.** `canon.mjs` (recursive sorted keys, `JSON.stringify` per scalar) and `canon.py`
(`json.dumps(sort_keys=True, separators=(',',':'), ensure_ascii=False)`), sha256 over UTF-8 bytes. Inputs read
from the working tree at the revisions in `../SOURCE_INVENTORY.md` §2.

| Source | JS sha256 (prefix) | Python sha256 (prefix) | bytes JS / Py | agree |
|---|---|---|---|---|
| `CROSS_REGISTRY_CLAIM_MAP.json` (v2.6) | `6b2fb9d2…` | `6b2fb9d2…` | 77,250 / 77,250 | yes |
| `evidence_state.json` (v2.6) | `a4307573…` | `a4307573…` | 26,166 / 26,166 | yes |
| `10_MACHINE_READABLE_LEDGER.json` (v2.6) | `2ce9040c…` | `360b6c60…` | 28,346 / 28,348 | **no** |
| `cells.json` (v0.8) | `7250d835…` | `7250d835…` | 58,045 / 58,045 | yes |
| `invariant-grid.json` (v1.69.0) | `ed76b935…` | `ed76b935…` | 691,717 / 691,717 | yes |
| `CLAIM_LEDGER.json` (ref `invariant-canonical`) | `7f2ec02e…` | `7f2ec02e…` | 423,214 / 423,214 | yes |

**Cause of the one divergence.** `/claims/18/confidence` is the JSON number `1.0`; Python serializes it `1.0`, JS
serializes it `1`. The other 18 floats (`0.9`, `0.75`, …) agree. This is the same defect class TRAAVIIS recorded
against RFC 8785 (`"reward":1.0` vs `"reward":1` moving a live `episode-` id).

**Rule the spec adopts (§6).** Normalized records carry no native floats. A source float is carried as the decimal
string exactly as it appears in the source bytes (`"1.0"`, not `1`), plus its JSON path, so the fact is preserved and the
canonical bytes are language-independent. Non-ASCII strings are carried as UTF-8 without `\u` escaping (both languages
agree on that form, as the five agreeing files show, 145–800 non-ASCII strings each).

**Reproduce.** `node canon.mjs <files>` and `python3 canon.py <files>` (the two scripts are ≤ 12 lines each and are
reproduced in `../G0_G1_SPEC.md` §6).
