#!/usr/bin/env python3
"""검증 경고 두 건을 교정한다 (Resources 파일 직접 정리).

_raw 원본 없이도 동작하도록, 이미 반영된 Resources 파일을 손본다.

1) NAB 역대상 28장 등 — 절 번호가 1..M로 이어지다 공백 뒤에 뜬금없이
   높은 번호 절(다음 장 소제목이 절로 잡힌 것)이 붙은 경우: 그 꼬리 절을
   버리고 앞의 연속 구간만 남긴다.

2) 주석 성경(knbnotes) — 일부 책이 normalize 안 된 원본 상태로 섞여
   각주 마커·"N장 머리글" 헤더·주석 문단이 절로 들어가 번호가 밀렸다.
   깨끗한 knb(성경) 본문을 기준으로, knbnotes 각 장의 항목을 순서대로
   정렬해 실제 절만 남기고(각주 마커 제거) knb 번호에 맞춘다. 헤더·주석
   문단처럼 knb 절과 대응되지 않는 항목은 버린다.

사용법:
    python3 scripts/fix_edition_warnings.py
    python3 scripts/validate_bible_text.py
"""
from __future__ import annotations

import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RES = REPO_ROOT / "CatholicBible" / "Resources"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import normalize_bible_text as nz  # noqa: E402

FOOTNOTE_RE = re.compile(r"(?<!\()\s*\b\d{1,3}\)")
WS_RE = re.compile(r"\s+")


def console_utf8() -> None:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass


def load(ed: str) -> dict:
    return json.loads((RES / f"BibleText_{ed}.json").read_text(encoding="utf-8"))


def save(ed: str, data: dict) -> None:
    (RES / f"BibleText_{ed}.json").write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )


# ── 1) 공백 뒤 꼬리 절 제거 (모든 판본) ──────────────────────────────

def drop_trailing_after_gap(books: dict) -> int:
    removed = 0
    for chapters in books.values():
        for ch, verses in list(chapters.items()):
            nums = sorted(int(k) for k in verses)
            # 1..M 연속 구간의 끝 M을 찾는다
            m = 0
            for i, n in enumerate(nums):
                if n == i + 1:
                    m = n
                else:
                    break
            # 안전장치: 1절부터 시작하지 않으면(m==0) 손대지 않는다
            if m == 0 or m == nums[-1]:
                continue
            # M 뒤(공백 건너뛴) 절이 있으면 제거
            for k in list(verses):
                if int(k) > m:
                    del verses[k]
                    removed += 1
            chapters[ch] = verses
    return removed


# ── 2) knbnotes를 knb 기준으로 정렬 교정 ─────────────────────────────

def norm_for_match(t: str) -> str:
    t = FOOTNOTE_RE.sub(" ", t)
    t = re.sub(r"[^0-9A-Za-z가-힣]", "", t)  # 한글/영숫자만 남겨 비교
    return t


def similar(a: str, b: str) -> float:
    a2, b2 = norm_for_match(a)[:40], norm_for_match(b)[:40]
    if not a2 or not b2:
        return 0.0
    return SequenceMatcher(None, a2, b2).ratio()


def realign_to_reference(notes_ch: dict, ref_ch: dict) -> dict:
    """notes_ch(주석성경 한 장)의 항목을 ref_ch(성경 한 장) 절에 순서대로
    맞춰 실제 절만 남기고 번호를 ref에 맞춘다."""
    notes = [notes_ch[k] for k in sorted(notes_ch, key=lambda k: int(k))]
    ref = [(k, ref_ch[k]) for k in sorted(ref_ch, key=lambda k: int(k))]
    out: dict[str, str] = {}
    j = 0  # notes 포인터
    for ref_num, ref_text in ref:
        # ref 절과 가장 잘 맞는 notes 항목을 앞에서부터 찾는다(최대 6칸 전방 탐색)
        best_k, best_score = -1, 0.0
        for k in range(j, min(j + 6, len(notes))):
            s = similar(notes[k], ref_text)
            if s > best_score:
                best_score, best_k = s, k
        if best_k >= 0 and best_score >= 0.55:
            text = WS_RE.sub(" ", FOOTNOTE_RE.sub(" ", notes[best_k])).strip()
            out[str(ref_num)] = text
            j = best_k + 1
        else:
            # 대응 항목을 못 찾으면 knb 본문으로 채운다(번역 동일 계열)
            out[str(ref_num)] = WS_RE.sub(" ", ref_text).strip()
    return out


def fix_knbnotes() -> tuple[int, int]:
    notes = load("knbnotes")
    ref = load("knb")["books"]
    changed_ch = 0
    changed_books = 0
    for book_id, chapters in notes["books"].items():
        if book_id not in ref:
            continue
        book_changed = False
        for ch, verses in chapters.items():
            if ch not in ref[book_id]:
                continue
            ref_ch = ref[book_id][ch]
            # 이미 번호가 ref와 같고 각주 마커도 없으면 건너뜀
            need = (len(verses) != len(ref_ch)
                    or any(FOOTNOTE_RE.search(v) for v in verses.values())
                    or sorted(int(k) for k in verses) != list(range(1, len(ref_ch) + 1)))
            if not need:
                continue
            chapters[ch] = realign_to_reference(verses, ref_ch)
            changed_ch += 1
            book_changed = True
        if book_changed:
            changed_books += 1
    save("knbnotes", notes)
    return changed_books, changed_ch


def main() -> None:
    console_utf8()
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--realign-knbnotes", action="store_true",
                    help="주석 성경을 knb 기준으로 정렬 교정(주석이 제거되어 knb와 거의 같아짐). "
                         "기본은 실행하지 않는다 — 주석을 보존하려면 이 옵션을 켜지 말 것.")
    args = ap.parse_args()

    # 1) NAB 등: 공백 뒤 꼬리 절(다음 장 소제목이 절로 잡힌 것) 제거
    for ed in ["nab", "knb", "ncb", "vulgata", "b200"]:
        data = load(ed)
        removed = drop_trailing_after_gap(data["books"])
        if removed:
            save(ed, data)
            print(f"[{ed}] 공백 뒤 꼬리 절 {removed}개 제거")

    # 2) 주석 성경 정렬 교정 (선택) — 주석이 사라지므로 기본 비활성
    if args.realign_knbnotes:
        nb, nc = fix_knbnotes()
        print(f"[knbnotes] knb 기준 정렬 교정: 책 {nb}권 / 장 {nc}개 (주석 제거됨)")
    else:
        print("[knbnotes] 주석 보존 — 재정렬 건너뜀 (필요시 --realign-knbnotes)")

    print("\n검증: python3 scripts/validate_bible_text.py")


if __name__ == "__main__":
    main()
