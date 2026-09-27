#!/usr/bin/env bash
# Turn the collected monthly summaries into the tabular data the availability chart
# draws, so the chart and the tables read the same numbers. Run from the source tree
# after the data branch is laid over it; does nothing when nothing is collected yet.
set -euo pipefail

months="Module:가용성/months.json"
[ -e "$months" ] || { echo "no $months yet"; exit 0; }

jq 'def pct: if . == null then null else . * 10000 | round / 100 end;
{
  license: "CC0-1.0",
  description: {ko: "페미위키의 월별 가용성(%)"},
  schema: {fields: [
    {name: "month", type: "string", title: {ko: "달"}},
    {name: "main", type: "number", title: {ko: "페미위키:대문"}},
    {name: "blank", type: "number", title: {ko: "특수:빈문서"}},
    {name: "ga4", type: "number", title: {ko: "GA4 세션"}}
  ]},
  data: [.[] | [
    .month,
    (.checks["페미위키:대문"].uptime | pct),
    (.checks["특수:빈문서"].uptime | pct),
    (.checks["GA4 세션"].uptime | pct)
  ]]
}' "$months" > "Data:가용성.tab"
