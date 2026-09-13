#!/usr/bin/env python3
"""Word error rate. Gold file vs hypothesis file. Prints wer=0.123 n=N."""
import re
import sys


def words(path: str) -> list[str]:
    text = open(path, encoding="utf-8").read().lower()
    return re.findall(r"[a-z0-9']+", text)


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


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: wer.py gold.txt hyp.txt", file=sys.stderr)
        sys.exit(2)
    ref, hyp = words(sys.argv[1]), words(sys.argv[2])
    print(f"wer={wer(ref, hyp):.4f} n={len(ref)} hyp={len(hyp)}")


if __name__ == "__main__":
    main()
