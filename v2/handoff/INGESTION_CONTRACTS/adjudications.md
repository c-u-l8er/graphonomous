# Ingestion contract — adjudications (GPT rulings, Travis rulings, factory round receipts)

**State:** DESIGNED 2026-09-02 (no code). ADVISORY sources produce `ADJUDICATION` nodes and `ADJUDICATED_BY` edges; they
never change an evidence state — only a registry record does, and the registry says whether it did (spec §5).

## Pin and sources
| Source | Path | Identity | Authority attribute |
|---|---|---|---|
| GPT research adjudication | `invariant-r10/package-v2.6/inputs/FABLE51_RESEARCH_GPT56_ADJUDICATION_FOR_OPUS.md` | sha256 of the file | `advisory` |
| GPT v2 audit | `…/inputs/FABLE51_R10PRE_V2_GPT56_AUDIT_FOR_OPUS.md` | sha256 | `advisory` |
| GPT execution adjudications v1/v2/v3 | `invariant-r10/inputs-gpt-execution-adjudication*.md` (+ copies under `package-v2.6/inputs/`; byte-equality checked by R7B) | sha256 | `advisory` |
| GPT note #1 on Graphonomous | `graphonomous/v2/handoff/research/PRIOR_LANE_GPT_NOTE.md` | sha256 | `advisory` (not a dataset source; recorded for provenance of this lane's premise) |
| Travis rulings | `ProjectAmp2/REVISION_REGISTER.md` rows R1…R43 | sha256 + row number | `ruling` |
| Factory round receipts | `mosaic/receipts/INV-R*.json` (via the factory adapter) | blob OID | `factory` |

## Records yielded
| Source element | Kind | Logical id | Notes |
|---|---|---|---|
| a Markdown section (`# 1. S6? ruling — ACCEPT the reduction to S1`) | `ADJUDICATION` | `adjudication:gpt:<doc-short>:§<n>` where `<n>` is the leading heading number | `disposition` parsed from the heading's ALL-CAPS token when present (`ACCEPT`, `REVISE`, `BLOCKER`, `ACCEPT WITH CAUTION`); the section text is stored verbatim as `text`; the anchor is the heading line number and its slug |
| citations inside registry records (`GPT v3 §1`, `GPT v2 §6`) | `ADJUDICATED_BY` from the citing record to the section | — | regex `GPT v(\d) §(\d+(?:[–-]\d+)?)`; a document version that does not exist in the pin → `UNPARSEABLE_CITATION`; a range `§1–§7` yields one edge per section |
| the `S6?` framing rule (v2 audit §6) and the acceptance (execution v1 §1) | `ADJUDICATION` nodes used by acceptance test A1 | — | verified to exist this round (lines 353–369 and 116–172 of the respective files at snapshot) |
| `REVISION_REGISTER.md` rows | `ADJUDICATION` (`authority: ruling`) | `adjudication:travis:R<n>` | `when`, `by` columns verbatim; rows marked `[OPEN]`/`[UNRULED]` get `disposition: open` |

## What this adapter must not do
Infer that a claim's state changed because a ruling said it should; resolve a disagreement between an adjudication and
a registry (that is a G1 diagnostic with both assertions shown); paraphrase.

## Faults
`UNPARSEABLE_CITATION` · `HEADING_WITHOUT_NUMBER` (a section cited by number that has no numbered heading) ·
`DUPLICATE_SECTION_NUMBER` (two headings with one number in a document — a real risk in these files).
