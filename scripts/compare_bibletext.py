#!/usr/bin/env python3
"""두 개의 BibleText_*.json 을 대조해 차이를 리포트한다.

새로 수집한 본문(fresh)을 현재 반영본(current)과 비교해, 어느 절이
- 한쪽에만 있는지(누락/추가),
- 본문(한글)이 다른지
를 보여 준다. 새 수집본으로 '통째로 덮어쓰기' 전에, 수작업으로 고쳐 둔
부분이 되돌아가지 않는지 눈으로 확인하는 용도다.

사용법:
    python scripts/compare_bibletext.py CURRENT.json FRESH.json
    python scripts/compare_bibletext.py CatholicBible/Resources/BibleText_knb.json \
                                        CatholicBible/Resources/BibleText_knb_fresh.json
    # 특정 책만, 본문 차이 전체 출력
    python scripts/compare_bibletext.py cur.json fresh.json --books sir 1chr --full
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def kc(t: str) -> str:
    """각주 마커를 뺀 한글 글자만 (표기·띄어쓰기 차이는 무시, 실제 본문 비교)."""
    return "".join(re.findall(r"[가-힣]", re.sub(r"(?<![\d(])\d{1,3}\)", "", t or "")))


def load_books(path: str) -> dict:
    d = json.loads(Path(path).read_text(encoding="utf-8"))
    return d.get("books", d)


def main() -> None:
    ap = argparse.ArgumentParser(description="BibleText JSON 두 개 대조")
    ap.add_argument("current")
    ap.add_argument("fresh")
    ap.add_argument("--books", nargs="*", help="이 책 id 만 비교")
    ap.add_argument("--full", action="store_true", help="본문 차이를 전부 출력")
    args = ap.parse_args()

    cur = load_books(args.current)
    fresh = load_books(args.fresh)
    books = args.books or sorted(set(cur) | set(fresh))

    only_cur, only_fresh, textdiff = [], [], []
    for bid in books:
        a, b = cur.get(bid, {}), fresh.get(bid, {})
        for cn in sorted(set(a) | set(b), key=lambda x: int(x)):
            av, bv = a.get(cn, {}), b.get(cn, {})
            for v in sorted(set(av) - set(bv), key=lambda x: int(x)):
                only_cur.append(f"{bid} {cn},{v}")
            for v in sorted(set(bv) - set(av), key=lambda x: int(x)):
                only_fresh.append(f"{bid} {cn},{v}")
            for v in sorted(set(av) & set(bv), key=lambda x: int(x)):
                if kc(av[v]) != kc(bv[v]):
                    textdiff.append((f"{bid} {cn},{v}", av[v], bv[v]))

    print(f"현재 파일 : {args.current}")
    print(f"새 수집본 : {args.fresh}")
    print(f"비교 대상 : {len(books)}권\n")
    print(f"● 현재에만 있는 절 : {len(only_cur)}")
    print("   ", ", ".join(only_cur[:40]) + (" …" if len(only_cur) > 40 else ""))
    print(f"● 새 수집본에만 있는 절 : {len(only_fresh)}")
    print("   ", ", ".join(only_fresh[:40]) + (" …" if len(only_fresh) > 40 else ""))
    print(f"● 본문(한글)이 다른 절 : {len(textdiff)}")
    show = textdiff if args.full else textdiff[:20]
    for ref, a, b in show:
        print(f"  [{ref}]")
        print(f"     현재: {a[:100]}")
        print(f"     신규: {b[:100]}")
    if not args.full and len(textdiff) > len(show):
        print(f"  … 외 {len(textdiff) - len(show)}건 (--full 로 전체 출력)")


if __name__ == "__main__":
    main()
