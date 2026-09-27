#!/usr/bin/env bash
# Turn the collected monthly summaries into the tabular data the availability chart
# draws: the hours each month in which the health checks failed, so the chart and the
# tables read the same numbers. Months before the health checks existed are left out,
# because a month with no bar would read as a month without trouble. Run from the source
# tree after the data branch is laid over it; does nothing when nothing is collected yet.
set -euo pipefail

months="Module:가용성/months.json"
[ -e "$months" ] || { echo "no $months yet"; exit 0; }

jq 'def lost: if . == null then null else (1 - .uptime) * .hours * 10 | round / 10 end;
{
  license: "CC0-1.0",
  description: {ko: "페미위키를 이용하지 못한 시간(월별)"},
  schema: {fields: [
    {name: "month", type: "string", title: {ko: "달"}},
    {name: "main", type: "number", title: {ko: "페미위키:대문"}},
    {name: "blank", type: "number", title: {ko: "특수:빈문서"}}
  ]},
  data: [.[] | select(.checks["페미위키:대문"] or .checks["특수:빈문서"]) | [
    .month,
    (.checks["페미위키:대문"] | lost),
    (.checks["특수:빈문서"] | lost)
  ]]
}' "$months" > "Data:가용성.tab"
