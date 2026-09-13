#!/usr/bin/env python3
"""Caption inventory + English-of-record chooser.

Never overwrites Whisper transcript.txt. Writes:
  transcript/captions_status.json
  transcript/canonical.en.txt
  transcript/canonical.json

usage: canonical.py status JOB
       canonical.py choose JOB
       canonical.py --selfcheck
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CJK = re.compile(r"[\u4e00-\u9fff]")
DEVANAGARI = re.compile(r"[\u0900-\u097f]")
LATIN = re.compile(r"[A-Za-z]")
WORD = re.compile(r"[A-Za-z0-9']+")
UNAVAILABLE = "[transcript unavailable]"
UNUSABLE = "[transcript unusable]"

EN_LANGS = ("en", "en-us", "en-gb", "en-orig", "eng", "eng-us", "eng-orig")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, json.JSONDecodeError):
        return {}


def dump(path: Path, doc: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def srt_text(path: Path) -> str:
    if not path.is_file():
        return ""
    lines = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        s = raw.strip()
        if not s or s.isdigit() or "-->" in s:
            continue
        lines.append(s)
    return "\n".join(lines).strip()


def is_en_lang(code: str) -> bool:
    c = (code or "").lower().replace("_", "-")
    return c in EN_LANGS or c.startswith("en-") or c.startswith("eng")


def list_tracks(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    out = []
    for p in sorted(root.rglob("*")):
        if p.suffix.lower() in {".srt", ".vtt", ".ttml"} and p.is_file() and p.stat().st_size > 0:
            out.append(p)
    return out


def lang_of(path: Path) -> str:
    return path.stem.lower()


def info_language(job: Path) -> str:
    for p in (job / "source").glob("*info.json"):
        info = load_json(p)
        for key in ("language", "original_language"):
            v = info.get(key)
            if isinstance(v, str) and v:
                return v.lower()
    print_j = load_json(job / "source" / "yt-dlp-print.json")
    v = print_j.get("language")
    if isinstance(v, str) and v:
        return v.lower()
    return ""


def pick_en(tracks: list[Path]) -> Path | None:
    ranked = []
    for p in tracks:
        lang = lang_of(p)
        if is_en_lang(lang):
            ranked.append((0 if lang in ("en", "en-orig", "eng") else 1, p))
    ranked.sort(key=lambda x: x[0])
    return ranked[0][1] if ranked else None


def captions_inventory(job: Path) -> dict:
    manual = list_tracks(job / "source" / "captions" / "manual")
    auto = list_tracks(job / "source" / "captions" / "auto")
    spoken = info_language(job)
    human_en = pick_en(manual)
    auto_en = pick_en(auto)
    primary = None
    kind = "none"
    gold = False
    if human_en:
        primary = str(human_en.relative_to(job))
        kind = "manual"
        gold = True
    elif auto_en:
        primary = str(auto_en.relative_to(job))
        kind = "auto"
    present = bool(manual or auto)
    src_human = next((p for p in manual if not is_en_lang(lang_of(p))), None)
    src_auto = next((p for p in auto if not is_en_lang(lang_of(p))), None)
    src = src_human or src_auto
    if src and spoken:
        # prefer matching spoken lang
        for p in (src_human, src_auto):
            if p and (lang_of(p).startswith(spoken[:2]) or spoken.startswith(lang_of(p)[:2])):
                src = p
                break
    doc = {
        "present": present,
        "kind": kind,
        "gold": gold,
        "spoken_lang": spoken or None,
        "langs": sorted({lang_of(p) for p in manual}),
        "auto_langs": sorted({lang_of(p) for p in auto}),
        "primary": primary,
        "source_track": str(src.relative_to(job)) if src else None,
        "url": None,
    }
    print_j = load_json(job / "source" / "yt-dlp-print.json")
    url = print_j.get("webpage_url")
    if isinstance(url, str):
        doc["url"] = url
    dump(job / "transcript" / "captions_status.json", doc)
    if src:
        text = srt_text(src)
        if text:
            (job / "transcript" / "source.txt").write_text(text + "\n", encoding="utf-8")
    return doc


def audio_s(job: Path) -> float:
    wav = job / "source" / "audio.wav"
    if not wav.is_file():
        return 0.0
    import subprocess

    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(wav)],
            text=True,
        ).strip()
        return float(out or 0)
    except (OSError, ValueError, subprocess.CalledProcessError):
        return 0.0


def srt_end_s(path: Path) -> float:
    if not path.is_file():
        return 0.0
    last = 0.0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "-->" not in line:
            continue
        right = line.split("-->")[-1].strip().split()[0]
        hms, _, ms = right.partition(",")
        if "." in right and "," not in right:
            hms, _, ms = right.partition(".")
        parts = hms.split(":")
        try:
            sec = int(parts[-1])
            mins = int(parts[-2]) if len(parts) > 1 else 0
            hrs = int(parts[-3]) if len(parts) > 2 else 0
            frac = int((ms + "000")[:3]) / 1000.0
            last = max(last, hrs * 3600 + mins * 60 + sec + frac)
        except ValueError:
            continue
    return last


def ngram_repeat(words: list[str], n: int = 4, thresh: float = 0.35) -> bool:
    if len(words) < n * 6:
        return False
    grams = [" ".join(words[i : i + n]) for i in range(len(words) - n + 1)]
    if not grams:
        return False
    from collections import Counter

    c = Counter(grams)
    top = c.most_common(1)[0][1]
    return (top / len(grams)) >= thresh


def whisper_unusable(job: Path, spoken: str) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    asr = load_json(job / "transcript" / "asr_status.json")
    status = str(asr.get("status") or "")
    text = ""
    tp = job / "transcript" / "transcript.txt"
    if tp.is_file():
        text = tp.read_text(encoding="utf-8", errors="replace").strip()
    if status in {"failed", "empty"} or text == UNAVAILABLE or not text:
        if status != "skipped":
            reasons.append("empty-or-failed")
    if status == "skipped":
        return False, ["asr-skipped"]
    if CJK.search(text):
        reasons.append("cjk-in-english")
    if DEVANAGARI.search(text):
        reasons.append("devanagari-in-english")
    letters = LATIN.findall(text)
    other = re.findall(r"\S", text)
    if other and len(letters) / max(len(other), 1) < 0.85 and spoken not in {"en", ""}:
        reasons.append("low-latin-ratio")
    words = WORD.findall(text.lower())
    dur = audio_s(job)
    if dur > 8 and words and (len(words) / dur) < 0.5:
        reasons.append("too-sparse")
    srt = job / "transcript" / "transcript.srt"
    end = srt_end_s(srt)
    if dur > 8 and end > 0 and (end / dur) < 0.80:
        reasons.append("srt-coverage")
    if ngram_repeat(words):
        reasons.append("loop")
    # Hindi-class: prefer captions even when Whisper returned latin text
    if spoken.startswith("hi"):
        reasons.append("hi-class")
    hard = [r for r in reasons if r != "asr-skipped"]
    return bool(hard), reasons


def choose(job: Path) -> dict:
    inv = captions_inventory(job)
    spoken = (inv.get("spoken_lang") or "").lower()
    asr = load_json(job / "transcript" / "asr_status.json")
    status = str(asr.get("status") or "")
    hyp_path = job / "transcript" / "transcript.txt"
    hyp = hyp_path.read_text(encoding="utf-8", errors="replace").strip() if hyp_path.is_file() else ""
    unusable, reasons = whisper_unusable(job, spoken)
    en_task = (spoken in {"", "en"} or spoken.startswith("en")) and status != "skipped"

    cap_path = Path(job / inv["primary"]) if inv.get("primary") else None
    cap_text = srt_text(cap_path) if cap_path else ""

    source = "whisper_en" if en_task else "whisper_tr"
    text = hyp
    if status == "skipped" and cap_text:
        source = "captions_human" if inv.get("kind") == "manual" else "captions_auto"
        text = cap_text
        reasons.append("asr-skipped-captions")
    elif unusable and cap_text:
        source = "captions_human" if inv.get("kind") == "manual" else "captions_auto"
        text = cap_text
    elif unusable and not cap_text:
        if not hyp or hyp == UNAVAILABLE:
            source = "unusable"
            text = UNUSABLE
        else:
            # keep Whisper, flag low confidence
            source = source
    if not text:
        source = "unusable"
        text = UNUSABLE

    canon = {
        "source": source,
        "lang": "en",
        "spoken_lang": spoken or None,
        "reason": reasons,
        "captions_kind": inv.get("kind"),
        "whisper_unusable": unusable,
    }
    dump(job / "transcript" / "canonical.json", canon)
    (job / "transcript" / "canonical.en.txt").write_text(text.rstrip() + "\n", encoding="utf-8")
    return canon


def selfcheck() -> int:
    import tempfile

    root = Path(tempfile.mkdtemp(prefix="ghost-canon-"))
    trans = root / "transcript"
    trans.mkdir(parents=True)
    (root / "source" / "captions" / "manual").mkdir(parents=True)
    (root / "source" / "yt-dlp-print.json").write_text(
        json.dumps({"language": "hi", "webpage_url": "https://example.test/x"}), encoding="utf-8"
    )
    (trans / "asr_status.json").write_text(json.dumps({"status": "ok"}), encoding="utf-8")
    (trans / "transcript.txt").write_text(
        "Anuchhed 1. All humans have the same birthright and freedom.\n", encoding="utf-8"
    )
    srt = root / "source" / "captions" / "manual" / "en.srt"
    srt.write_text(
        "1\n00:00:00,000 --> 00:00:04,000\nAll human beings are born free and equal in dignity and rights.\n",
        encoding="utf-8",
    )
    doc = choose(root)
    canon = (trans / "canonical.en.txt").read_text(encoding="utf-8")
    assert doc["source"] == "captions_human", doc
    assert "human beings" in canon.lower(), canon
    assert "hi-class" in doc["reason"], doc
    # English usable: whisper stays
    root2 = Path(tempfile.mkdtemp(prefix="ghost-canon-en-"))
    (root2 / "transcript").mkdir()
    (root2 / "source").mkdir()
    (root2 / "source" / "yt-dlp-print.json").write_text(
        json.dumps({"language": "en"}), encoding="utf-8"
    )
    (root2 / "transcript" / "asr_status.json").write_text(
        json.dumps({"status": "ok"}), encoding="utf-8"
    )
    (root2 / "transcript" / "transcript.txt").write_text(
        "The quick brown fox jumps over the lazy dog.\n", encoding="utf-8"
    )
    d2 = choose(root2)
    assert d2["source"] == "whisper_en", d2
    assert "quick brown fox" in (root2 / "transcript" / "canonical.en.txt").read_text()
    print("selfcheck ok")
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--selfcheck":
        return selfcheck()
    if len(sys.argv) != 3 or sys.argv[1] not in {"status", "choose"}:
        print("usage: canonical.py status|choose JOB", file=sys.stderr)
        return 2
    job = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "status":
        print(json.dumps(captions_inventory(job)))
        return 0
    print(json.dumps(choose(job)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
