#!/usr/bin/env python3
"""sanitize_bib.py — 공개 커밋 전 BibTeX 비식별화 규칙의 SSOT.

왜 별도 모듈인가
----------------
비식별화가 렌더 **뒤에** 붙어 있으면 citation key 자체가 치환되면서 정렬이
깨진다 (실측: `web-<company>gokweol` → `web-tbdhnygokweol` 로 바뀌어
`web-gordonnovakjr` 보다 뒤로 가야 할 키가 앞에 남았다). 그래서 규칙을 여기
한 곳에 두고

  · `gen-bibtex.py` 가 **정렬 전에** key/본문에 적용하고
  · `sanitize-public-bib.sh` 가 같은 규칙을 파일 단위로 위임한다.

raw 식별자 문자열은 파일에 직접 적지 않고 조합해서 만든다 (기존 shell 정책 동일).
치환 결과는 원본 토큰을 포함하지 않으므로 규칙은 멱등이다.

CLI:
    python3 sanitize_bib.py FILE [FILE...]   # in-place, 변경된 파일만 다시 쓴다
    python3 sanitize_bib.py --jq-filter      # 같은 규칙을 jq 필터로 출력
"""

import re
import sys

_COMPANY = "go" + "qual"
_HOST = "hej" + "dev"

# 규칙은 여기 한 곳에만 산다. 패턴은 Python 문법(`(?P<name>…`)으로 적고,
# jq(Oniguruma)용은 `(?<name>…` 로 기계적으로 변환해 내보낸다. 그래서
# gen-bibtex.py 와 gh-starred-to-bib.sh 가 **같은 규칙**을 쓰고 갈라질 수 없다.
_RULE_SPECS = [
    {"pattern": re.escape(_COMPANY), "py_repl": "tbdhny", "jq_repl": "tbdhny"},
    {
        "pattern": re.escape(_HOST) + r"(?P<d>[0-9]*)",
        "py_repl": r"urwqri\g<d>",
        "jq_repl": r"urwqri\(.d)",
    },
]

_RULES = [
    (re.compile(spec["pattern"], re.IGNORECASE), spec["py_repl"])
    for spec in _RULE_SPECS
]


def sanitize_text(text: str) -> str:
    """비식별화 규칙을 적용한다. 멱등."""
    if not text:
        return text
    for pattern, repl in _RULES:
        text = pattern.sub(repl, text)
    return text


def jq_filter() -> str:
    """같은 규칙을 jq 필터 문자열로 내보낸다.

    jq 파이프라인이 **정렬 전에** 키를 비식별화할 수 있게 한다. 렌더러에서
    겪었던 것과 같은 구조적 결함(정렬 뒤 치환 → 최종 바이트에 역전)이
    GitHub starred 경로에도 생기지 않도록, 규칙을 복제하지 않고 여기서 준다.
    """
    parts = []
    for spec in _RULE_SPECS:
        # Python `(?P<name>` → Oniguruma `(?<name>`
        pattern = spec["pattern"].replace("(?P<", "(?<")
        parts.append(
            'gsub("{}"; "{}"; "i")'.format(
                pattern.replace("\\", "\\\\").replace('"', '\\"'),
                spec["jq_repl"],
            )
        )
    return " | ".join(parts)


def sanitize_file(path: str) -> bool:
    """파일을 in-place 비식별화. 실제로 바뀐 경우에만 쓴다 (mtime 보호)."""
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()
    cleaned = sanitize_text(original)
    if cleaned == original:
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(cleaned)
    return True


def main(argv) -> int:
    if argv and argv[0] == "--jq-filter":
        print(jq_filter())
        return 0
    if not argv:
        print("usage: sanitize_bib.py [--jq-filter] | FILE [FILE...]", file=sys.stderr)
        return 2
    changed = 0
    for path in argv:
        if sanitize_file(path):
            changed += 1
    print(f"[OK] Sanitized {len(argv)} bib files ({changed} changed)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
