# Optional wiki / GBrain handoff

This repo is not a knowledge base. It produces a job directory. Filing into GBrain (or any wiki) is **optional and operator-gated**. Other harnesses can ignore this file.

## After ingest

1. Read `MANIFEST.json` + transcript. Open `frames/` only if `analyze_frames` is true or the operator asked.
2. Write `analysis/context.md`, `meaning.md`, `intent.md` (`prompts/understand.md`).
3. If the operator asked to save it into **their** brain: file by primary subject, cite the source URL, keep the job dir as provenance. Do not duplicate an existing page for the same URL.
4. A page without a transcript link is incomplete.

## Do not

- Auto-write a wiki from the container or from `scripts/purge.sh`
- Assume any memory store is installed
