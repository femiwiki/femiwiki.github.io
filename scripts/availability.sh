#!/usr/bin/env bash
# Hourly health of the site from Route 53's health checks, one file per month:
# Module:가용성/YYYY-MM.json holds, per check, the fraction of probes that passed in
# each hour of the month, Seoul time (null where there is no data). CloudWatch keeps hourly
# figures for 15 months, so a month can be fetched or refetched until then.
set -euo pipefail
out=$1
closed=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
if [ $# -ge 2 ]; then
  [[ "$2" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { echo "month must be YYYY-MM, got '$2'" >&2; exit 2; }
  months=("$2")
else
  months=("$(date -u -d "$closed-01 -1 day" +%Y-%m)" "$closed")
fi
mkdir -p "$out/Module:가용성" "$out/가용성"

# A check is known by the page it requests. Replacing a check gives it a new ID and
# CloudWatch keeps the old one's metrics, so the retired IDs stay listed here.
declare -A ids=(
  ["페미위키:대문"]="6f01b5f3-bb0c-44c8-8dd3-79be07f8cc54"
  ["특수:빈문서"]="c6722062-06b7-436b-b154-51e7e1cfca58"
)
while IFS=$'\t' read -r id path; do
  name=$(printf '%b' "${path//%/\\x}"); name=${name#/w/}
  ids[$name]="${ids[$name]:-} $id"
done < <(aws route53 list-health-checks --output json | jq -r '.HealthChecks[] | "\(.Id)\t\(.HealthCheckConfig.ResourcePath)"')

queries() { # month -> metric data queries for every ID, hourly Sum and SampleCount
  local i=0 q=()
  for name in "${!ids[@]}"; do
    for id in ${ids[$name]}; do
      for stat in Sum SampleCount; do
        q+=("{\"Id\":\"q$i\",\"Label\":\"$name|$stat\",\"MetricStat\":{\"Metric\":{\"Namespace\":\"AWS/Route53\",\"MetricName\":\"HealthCheckStatus\",\"Dimensions\":[{\"Name\":\"HealthCheckId\",\"Value\":\"$id\"}]},\"Period\":3600,\"Stat\":\"$stat\"}}")
        i=$((i + 1))
      done
    done
  done
  printf '[%s]' "$(IFS=,; echo "${q[*]}")"
}

# A month runs from midnight to midnight in Seoul, so the hours line up with the days
# the readers live in.
for month in "${months[@]}"; do
  start=$(date -u -d "$month-01T00:00:00+09:00" +%Y-%m-%dT%H:%M:%SZ)
  end=$(date -u -d "$(date -u -d "$month-01 +1 month" +%Y-%m-01)T00:00:00+09:00" +%Y-%m-%dT%H:%M:%SZ)
  TZ=UTC aws cloudwatch get-metric-data --output json --region us-east-1 \
    --start-time "$start" --end-time "$end" --metric-data-queries "$(queries "$month")" \
    | jq --sort-keys --arg month "$month" --arg start "$start" --arg end "$end" '
      def hour: (. | sub("\\+00:00$"; "Z") | fromdateiso8601 - ($start | fromdateiso8601)) / 3600 | floor;
      (($end | fromdateiso8601) - ($start | fromdateiso8601)) / 3600 as $hours
      | [.MetricDataResults[] | .Label as $label | [.Timestamps, .Values] | transpose[] | {label: $label, hour: (.[0] | hour), value: .[1]}]
      | group_by(.label | split("|")[0])
      | map({
          key: (.[0].label | split("|")[0]),
          value: (
            (map(select(.label | endswith("|Sum"))) | group_by(.hour) | map({key: (.[0].hour | tostring), value: (map(.value) | add)}) | from_entries) as $sum
            | (map(select(.label | endswith("|SampleCount"))) | group_by(.hour) | map({key: (.[0].hour | tostring), value: (map(.value) | add)}) | from_entries) as $count
            | [range($hours) | tostring | if $count[.] then (($sum[.] / $count[.]) * 10000 | round / 10000) else null end]
          )
        })
      | from_entries
      | {month: $month, hours: $hours, checks: .}' > "$out/Module:가용성/$month.json"
  printf '{{#invoke:Availability.lua|month|%s}}\n' "$month" > "$out/가용성/$month.wikitext"
  echo "$month"
done

for f in "$out"/Module:가용성/[0-9][0-9][0-9][0-9]-[0-9][0-9].json; do
  jq -c '{month, checks: (.checks | with_entries(.value = ((.value | map(select(. != null))) as $v | if ($v | length) > 0 then {hours: ($v | length), uptime: (($v | add) / ($v | length) * 1000000 | round / 1000000)} else null end)))}' "$f"
done | jq -s 'sort_by(.month)' > "$out/Module:가용성/months.json"
