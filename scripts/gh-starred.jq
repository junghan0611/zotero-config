# gh-starred.jq — GitHub starred 응답 → BibTeX 엔트리
#
# @@KEYSAN@@ 은 실행 시 `sanitize_bib.py --jq-filter` 결과로 치환된다.
# 비식별화를 **정렬 전에** 키에 적용해야 최종 바이트의 정렬 불변식이 성립한다
# (정렬 뒤에 치환하면 키가 바뀌면서 역전이 남는다 — Zotero 렌더러에서 겪은 것과
# 같은 구조적 결함).
add
| map(. + {bibkey: (.repo.full_name | gsub("[^a-zA-Z0-9]"; "") | @@KEYSAN@@)})
| sort_by(.bibkey)
| .[]
| .starred_at as $starred
| .bibkey as $key
| .repo
| (.topics | if length > 0 then join(", ") else "" end) as $keywords
| (.description // "" | gsub("[{}]"; "") | gsub("\""; "\\\"") | gsub("\n"; " ")) as $desc
| (.license.name // "") as $license
| ($starred | split("T")[0]) as $urldate
| ("@software{\($key),
  title = {\(.full_name)},
  author = {\(.owner.login)},
  date = {\(.updated_at)},
  origdate = {\(.created_at)},
  url = {\(.html_url)},
  urldate = {\($urldate)},
  abstract = {\($desc)},
  keywords = {\($keywords)},
  note = {stars: \(.stargazers_count), language: \(.language // "unknown"), license: \($license)},
  datemodified = {\(.pushed_at)},
  dateadded = {\($starred)}
}
"
# 키는 이미 정렬 전에 비식별화됐다. 본문 필드도 같은 규칙으로 여기서 처리해
# 렌더 결과 자체가 최종형이 되게 한다 (규칙이 멱등이라 키에 다시 걸려도 무해).
# sanitize-public-bib.sh 래퍼는 그 뒤의 안전망으로만 남는다.
  | @@KEYSAN@@)
