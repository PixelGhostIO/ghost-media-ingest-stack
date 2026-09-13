#!/usr/bin/env python3
"""Score bake-off transcripts: WER, entity recall, comprehension claims."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = json.loads((Path(__file__).with_name("bakeoff_spec.json")).read_text())


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def wer(ref: list[str], hyp: list[str]) -> float:
    n, m = len(ref), len(hyp)
    if n == 0:
        return 0.0 if m == 0 else 1.0
    dp = list(range(m + 1))
    for i, r in enumerate(ref, 1):
        prev, dp[0] = dp[0], i
        for j, h in enumerate(hyp, 1):
            cur = dp[j]
            dp[j] = prev if r == h else 1 + min(prev, dp[j], dp[j - 1])
            prev = cur
    return dp[m] / n


def norm(text: str) -> str:
    return " ".join(words(text))


def phrase_in(hay: str, phrase: str) -> bool:
    return norm(phrase) in hay


def entity_status(hay: str, ent: dict) -> str:
    for h in ent.get("hit") or []:
        if phrase_in(hay, h):
            return "hit"
    for n in ent.get("near") or []:
        if phrase_in(hay, n):
            return "near"
    return "miss"


def claim_hit(hay: str, claim: dict) -> bool:
    return any(phrase_in(hay, a) for a in claim.get("any") or [])


def source_leak(text: str, spec: dict) -> list[str]:
    leaks: list[str] = []
    scripts = spec.get("leak_scripts") or []
    if "cjk" in scripts and re.search(r"[\u4e00-\u9fff]", text):
        leaks.append("cjk")
    if "devanagari" in scripts and re.search(r"[\u0900-\u097f]", text):
        leaks.append("devanagari")
    low = text.lower()
    for p in spec.get("leak_phrases") or []:
        if p.lower() in low:
            leaks.append(p)
    return leaks


def read_transcript(run_dir: Path) -> str:
    p = run_dir / "transcript.txt"
    if not p.is_file():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")


def read_bench(run_dir: Path) -> dict:
    p = run_dir / "bench.json"
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return {}


def score_text(text: str, spec: dict, gold_words: list[str] | None) -> dict:
    hay = norm(text)
    ents = []
    hits = near = miss = 0
    for ent in spec.get("entities") or []:
        st = entity_status(hay, ent)
        ents.append({"id": ent["id"], "status": st})
        if st == "hit":
            hits += 1
        elif st == "near":
            near += 1
        else:
            miss += 1
    n_ent = max(hits + near + miss, 1)
    claims = []
    chits = 0
    for c in spec.get("claims") or []:
        ok = claim_hit(hay, c)
        claims.append({"id": c["id"], "hit": ok})
        chits += int(ok)
    n_cl = max(len(spec.get("claims") or []), 1)
    out = {
        "entity_hits": hits,
        "entity_near": near,
        "entity_miss": miss,
        "entity_n": hits + near + miss,
        "entity_recall": round(hits / n_ent, 3),
        "claims_hit": chits,
        "claims_n": len(spec.get("claims") or []),
        "comprehension": round(chits / n_cl, 3),
        "entities": ents,
        "claims": claims,
        "hyp_words": len(words(text)),
        "source_leak": source_leak(text, spec),
    }
    if gold_words is not None:
        hyp = words(text)
        out["wer"] = round(wer(gold_words, hyp), 4)
        out["gold_words"] = len(gold_words)
    return out


def score_level(out_root: Path, level: str) -> dict:
    spec = SPEC[level]
    gold_words = None
    if spec.get("gold"):
        gold_words = words((ROOT / spec["gold"]).read_text(encoding="utf-8"))
    arms = {}
    for arm_dir in sorted((out_root / level).iterdir() if (out_root / level).is_dir() else []):
        if not arm_dir.is_dir():
            continue
        arm = arm_dir.name
        rec = {"arm": arm}
        for pass_name in ("cold", "warm"):
            d = arm_dir / pass_name
            if not d.is_dir():
                continue
            text = read_transcript(d)
            bench = read_bench(d)
            status = "ok"
            asr = d / "asr_status.json"
            if asr.is_file():
                try:
                    status = json.loads(asr.read_text()).get("status", status)
                except json.JSONDecodeError:
                    status = "unknown"
            if not text.strip() or text.strip() == "[transcript unavailable]":
                status = "failed"
            rss = float(bench.get("peak_rss_mb") or 0)
            if rss > 12000:
                status = "oom"
            rec[pass_name] = {
                "status": status,
                "bench": {
                    "wall_s": bench.get("wall_s"),
                    "rtf": bench.get("rtf"),
                    "peak_rss_mb": bench.get("peak_rss_mb"),
                    "audio_s": bench.get("audio_s"),
                    "model": bench.get("model"),
                    "device": bench.get("device"),
                },
                **score_text(text, spec, gold_words),
            }
        arms[arm] = rec
    # pairwise WER vs cpp-large warm (not gold)
    ref_text = ""
    if "cpp-large" in arms and "warm" in arms["cpp-large"]:
        ref_path = out_root / level / "cpp-large" / "warm" / "transcript.txt"
        if ref_path.is_file():
            ref_text = ref_path.read_text(encoding="utf-8", errors="replace")
    if ref_text.strip() and ref_text.strip() != "[transcript unavailable]":
        ref_w = words(ref_text)
        for arm, rec in arms.items():
            warm = rec.get("warm")
            if not warm:
                continue
            hyp_path = out_root / level / arm / "warm" / "transcript.txt"
            if not hyp_path.is_file():
                continue
            hyp = words(hyp_path.read_text(encoding="utf-8", errors="replace"))
            warm["wer_vs_cpp_large"] = round(wer(ref_w, hyp), 4)
    doc = {"level": level, "task": spec.get("task"), "lang": spec.get("lang"), "arms": arms}
    dest = out_root / level / "score.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(doc, indent=2) + "\n")
    return doc


def main() -> None:
    out_root = ROOT / "work" / "_bakeoff"
    levels = sys.argv[1:] or [p.name for p in sorted(out_root.iterdir()) if p.is_dir() and p.name in SPEC]
    summary = []
    for level in levels:
        if level not in SPEC:
            print(f"unknown level {level}", file=sys.stderr)
            continue
        doc = score_level(out_root, level)
        summary.append(doc)
        print(f"# {level}")
        for arm, rec in doc["arms"].items():
            w = rec.get("warm") or rec.get("cold") or {}
            bench = w.get("bench") or {}
            print(
                f"{arm:12} status={w.get('status')} wall={bench.get('wall_s')} "
                f"rtf={bench.get('rtf')} rss={bench.get('peak_rss_mb')} "
                f"wer={w.get('wer')} ents={w.get('entity_hits')}/{w.get('entity_n')} "
                f"claims={w.get('claims_hit')}/{w.get('claims_n')} "
                f"leak={w.get('source_leak')}"
            )
        print()
    (out_root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
