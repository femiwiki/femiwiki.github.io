#!/usr/bin/env bash
# Turn the collected bills into the tabular data the cost charts draw: each service's
# usage before credits, the way the month pages count it, so a month that credits paid
# for in full still shows where the money went. One pie table per month, one summing the
# latest twelve months, and one stacking every month by service for the cost page.
# Services under one percent of their table are folded into one "기타" when there are two
# or more of them. Run from the source tree after the data branch is laid over it; does
# nothing when nothing is collected yet.
set -euo pipefail

months="Module:비용/months.json"
[ -e "$months" ] || { echo "no $months yet"; exit 0; }

# Service name and usage pairs for one month, from the console's bill when it was
# captured, else from Cost Explorer grouped by service and record type.
usage() {
  local dir="Module:비용/$1"
  if [ -e "$dir/bill.json" ]; then
    jq -c --arg month "$1" '.services[] | {month: $month, name, usage: ([.. | .items? // empty | .[] | select(.type != "Credit") | .amount] | add // 0)}' "$dir/bill.json"
  elif [ -e "$dir/cost.json" ]; then
    jq -c --arg month "$1" '.ResultsByTime[0].Groups[] | select(.Keys[1] | IN("Tax", "Credit", "Refund") | not)
      | {month: $month, name: .Keys[0], usage: (.Metrics.UnblendedCost.Amount | tonumber)}' "$dir/cost.json"
  fi
}

# The services worth their own slice or band among the given rows: at least one percent
# of the total, unless only one service falls under that. Tabular field names take ASCII
# identifiers alone, so the columns are numbered and the service names go in the titles.
header=$(cat <<'EOF'
  def cents: . * 100 | round / 100;
  def kept: group_by(.name) | map({name: .[0].name, usage: (map(.usage) | add)})
    | (map(.usage) | add // 0) as $total
    | map(select(.usage >= 0.005)) | sort_by(-.usage)
    | (map(select(.usage < $total / 100)) | length) as $small
    | map(select($small < 2 or .usage >= $total / 100) | .name);
  def bucket($kept): if IN($kept[]) then . else "기타" end;
  def fields($first): {fields: ([$first] + (to_entries | map({name: "s\(.key)", type: "number", title: {ko: .value}})))};
EOF
)

# A pie draws each column as a slice, so its table is one row with a column per service.
pie() {
  jq -s --arg description "$1" --arg period "$2" "$header"'
    kept as $kept | map(.name |= bucket($kept)) | group_by(.name)
    | map({name: .[0].name, usage: (map(.usage) | add)}) | map(select(.usage >= 0.005)) | sort_by(-.usage)
    | {
        license: "CC0-1.0",
        description: {ko: $description},
        schema: (map(.name) | fields({name: "period", type: "string", title: {ko: "기간"}})),
        data: [[$period] + map(.usage | cents)]
      }'
}

mapfile -t all < <(jq -r '.[].month' "$months")
rows=$(mktemp)
for m in "${all[@]}"; do usage "$m"; done > "$rows"

mkdir -p "Data:비용"
for m in "${all[@]}"; do
  jq -c --arg m "$m" 'select(.month == $m)' "$rows" | pie "$m 서비스별 AWS 사용 금액" "$m" > "Data:비용/$m.tab"
done
recent=$(printf '%s\n' "${all[@]: -12}" | jq -R . | jq -s -c .)
jq -c --argjson recent "$recent" 'select(.month | IN($recent[]))' "$rows" \
  | pie "최근 12달 서비스별 AWS 사용 금액" "최근 12달" > "Data:비용.tab"

# Every month as a row and every kept service as a column, largest first, so the bands
# stack with the biggest at the bottom.
jq -s "$header"'
  kept as $kept | map(.name |= bucket($kept)) as $rows
  | ($kept + (if any($rows[]; .name == "기타") then ["기타"] else [] end)) as $names
  | {
      license: "CC0-1.0",
      description: {ko: "달마다 서비스별 AWS 사용 금액"},
      schema: ($names | fields({name: "month", type: "string", title: {ko: "달"}})),
      data: [$rows | group_by(.month)[] | . as $m
        | [$m[0].month] + [$names[] as $n | [$m[] | select(.name == $n) | .usage] | add // 0 | cents]]
    }' "$rows" > "Data:비용 추이.tab"
rm -f "$rows"
