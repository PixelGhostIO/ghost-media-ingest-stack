#!/usr/bin/env python3
"""Build a short whisper --prompt from job metadata + first transcript.

Does not detect language. Does not ship regional word lists.
Terms come from this job's title, tags, description, and transcript.
Writes <job>/transcript/auto-prompt.txt

usage: auto_prompt.py JOB_DIR
       auto_prompt.py --selfcheck
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

STOP = frozenset(
    """
    a an the and or but if then so of to for from in on at by with as is are was
    were be been being this that these those it its you your we our they them he
    she his her their not no yes do does did doing have has had just about into
    over after before than too very can will would should could all any some more
    most other such only own same because until while during both few each
    official video music watch subscribe channel episode podcast official
    """.split()
)
TOKEN = re.compile(r"[^\W\d_][\w'-]{2,}", re.UNICODE)
URL = re.compile(r"https?://\S+")
MAX_DEFAULT = 32


def tokens(text: str) -> list[str]:
    text = URL.sub(" ", text or "")
    out = []
    for m in TOKEN.finditer(text):
        w = m.group(0).strip("-'")
        if len(w) < 3:
            continue
        if w.lower() in STOP:
            continue
        out.append(w)
    return out


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, json.JSONDecodeError):
        return {}


def harvest(job: Path) -> list[str]:
    source, trans = job / "source", job / "transcript"
    ranked: list[tuple[int, str]] = []  # lower rank = earlier in prompt
    seen: set[str] = set()

    def add(words: list[str], rank: int) -> None:
        for w in words:
            key = w.lower()
            if key in seen:
                continue
            seen.add(key)
            ranked.append((rank, w))

    title = channel = ""
    tags: list[str] = []
    print_j = load_json(source / "yt-dlp-print.json")
    if print_j:
        title = str(print_j.get("title") or "")
        channel = str(print_j.get("channel") or "")
    info = {}
    for p in source.glob("*info.json"):
        info = load_json(p)
        if info:
            title = title or str(info.get("title") or "")
            channel = channel or str(info.get("channel") or info.get("uploader") or "")
            raw = info.get("tags") or []
            if isinstance(raw, list):
                tags = [str(t) for t in raw]
            break
    desc = ""
    for p in list(source.glob("*.description")) + list(source.glob("*description*")):
        try:
            desc = p.read_text(encoding="utf-8", errors="replace")
            break
        except OSError:
            pass

    add(tokens(title), 0)
    add(tokens(" ".join(tags)), 1)
    add(tokens(channel), 2)
    add(tokens(desc[:4000]), 3)

    tpath = trans / "transcript.txt"
    if tpath.is_file():
        body = tpath.read_text(encoding="utf-8", errors="replace")
        if "[transcript unavailable]" not in body:
            # rare-ish transcript tokens (not stop, length>=4): likely names
            counts: dict[str, int] = {}
            keep: list[str] = []
            for w in tokens(body):
                if len(w) < 4:
                    continue
                k = w.lower()
                counts[k] = counts.get(k, 0) + 1
                if k not in seen:
                    keep.append(w)
            add([w for w in keep if 1 <= counts[w.lower()] <= 6][:40], 4)

    ranked.sort(key=lambda x: x[0])
    return [w for _, w in ranked]


def render(terms: list[str], limit: int) -> str:
    terms = terms[:limit]
    if not terms:
        return ""
    return "Proper nouns: " + ", ".join(terms) + "."


def write_job(job: Path, limit: int) -> Path:
    trans = job / "transcript"
    trans.mkdir(parents=True, exist_ok=True)
    text = render(harvest(job), limit)
    out = trans / "auto-prompt.txt"
    out.write_text(text + ("\n" if text else ""), encoding="utf-8")
    return out


def selfcheck() -> None:
    import tempfile

    t = Path(tempfile.mkdtemp())
    (t / "source").mkdir()
    (t / "transcript").mkdir()
    (t / "source" / "yt-dlp-print.json").write_text(
        json.dumps(
            {
                "title": "WidgetCorp FooBar ACME-9",
                "channel": "TechTalks",
                "tags": ["FooBar", "the"],
            }
        ),
        encoding="utf-8",
    )
    (t / "transcript" / "transcript.txt").write_text(
        "the widgetcorp launch of foobar and a uniquehexname only once\n",
        encoding="utf-8",
    )
    p = write_job(t, 32)
    body = p.read_text(encoding="utf-8")
    assert "WidgetCorp" in body or "widgetcorp" in body.lower(), body
    assert "FooBar" in body or "foobar" in body.lower(), body
    assert " uniquehexname" in f" {body.lower()}" or "uniquehexname" in body.lower(), body
    assert " the," not in f" {body.lower()} ", body
    print("selfcheck ok", body.strip())


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--selfcheck":
        selfcheck()
        return
    if len(sys.argv) < 2:
        print("usage: auto_prompt.py JOB_DIR", file=sys.stderr)
        sys.exit(2)
    job = Path(sys.argv[1])
    limit = int(__import__("os").environ.get("GHOST_AUTO_PROMPT_MAX", MAX_DEFAULT))
    out = write_job(job, limit)
    text = out.read_text(encoding="utf-8").strip()
    n = 0 if not text else text.count(",") + (1 if text else 0)
    print(f"auto-prompt terms={n} path={out}")


if __name__ == "__main__":
    main()
