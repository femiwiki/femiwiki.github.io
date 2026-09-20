#!/usr/bin/env bash
# Hourly health of the site, one file per month: Module:가용성/YYYY-MM.json holds, per
# series, a value for each hour of the month in Seoul time (null where there is no data).
# Route 53's health checks give the fraction of probes that passed; CloudWatch keeps that
# hourly for 15 months. Google Analytics, when GA_SERVICE_ACCOUNT holds the service
# account's key, gives the hour's sessions against what that hour of the day usually
# brought in the month, capped at 1: traffic that stops is the site that stopped, and it
# reaches back to 2021.
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

ga_token() {
  local key header claim sig now
  key=$GA_SERVICE_ACCOUNT
  b64() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64)
  claim=$(jq -cn --arg iss "$(jq -r .client_email <<< "$key")" --argjson iat "$now" --argjson exp "$((now + 3600))" \
    '{iss: $iss, scope: "https://www.googleapis.com/auth/analytics.readonly", aud: "https://oauth2.googleapis.com/token", iat: $iat, exp: $exp}' | b64)
  sig=$(printf '%s.%s' "$header" "$claim" | openssl dgst -sha256 -sign <(jq -r .private_key <<< "$key") | b64)
  curl -fsS -X POST https://oauth2.googleapis.com/token \
    -d grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer -d "assertion=$header.$claim.$sig" | jq -r .access_token
}

# Sessions per hour of the month, from the property's own time zone (Seoul).
ga_sessions() { # month -> json array of hourly session counts
  local first last
  first="$1-01"
  last=$(date -u -d "$1-01 +1 month -1 day" +%Y-%m-%d)
  curl -fsS -H "Authorization: Bearer $ga_token" -H 'Content-Type: application/json' \
    "https://analyticsdata.googleapis.com/v1beta/properties/$ga_property:runReport" \
    -d "{\"dateRanges\":[{\"startDate\":\"$first\",\"endDate\":\"$last\"}],\"dimensions\":[{\"name\":\"dateHour\"}],\"metrics\":[{\"name\":\"sessions\"}],\"limit\":1000}" \
    | jq --arg first "$first" '
      ($first | strptime("%Y-%m-%d") | mktime) as $start
      | [.rows[]? | select(.dimensionValues[0].value | test("^[0-9]{10}$"))
         | {hour: ((.dimensionValues[0].value | strptime("%Y%m%d%H") | mktime) - $start) / 3600 | floor, n: (.metricValues[0].value | tonumber)}]
      | map({key: (.hour | tostring), value: .n}) | from_entries'
}

if [ -n "${GA_SERVICE_ACCOUNT:-}" ]; then
  ga_token=$(ga_token)
  ga_property=$(jq -r .property_id <<< "$GA_SERVICE_ACCOUNT")
fi

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
      ((($end | fromdateiso8601) - ($start | fromdateiso8601)) / 3600) as $hours
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
  if [ -n "${GA_SERVICE_ACCOUNT:-}" ]; then
    # An hour counts in full when it brought at least a quarter of what that hour of
    # the day usually brings in the month (the median, so an outage does not lower it),
    # and never less than one session.
    ga_sessions "$month" | jq --sort-keys --slurpfile cw "$out/Module:가용성/$month.json" '
      . as $sessions
      | $cw[0] as $cw
      | [range($cw.hours) | $sessions[tostring] // 0] as $n
      | [range(24) as $h | [range($h; $cw.hours; 24) | $n[.]] | sort | .[length / 2 | floor]] as $median
      | [range($cw.hours) as $i | ([1, ($median[$i % 24] / 4)] | max) as $t | ([1, ($n[$i] / $t)] | min * 10000 | round / 10000)] as $values
      | $cw | .checks["GA4 세션"] = $values' > "$out/Module:가용성/$month.json.ga" \
      && mv "$out/Module:가용성/$month.json.ga" "$out/Module:가용성/$month.json"
  fi
  # The month's page is where people write what happened, so it is made once and
  # never overwritten, wherever it lives.
  page="가용성/${month%-*}년 $((10#${month#*-}))월.wikitext"
  [ -e "$page" ] || [ -e "$out/$page" ] || printf '{{#invoke:Availability.lua|month|%s}}\n' "$month" > "$out/$page"
  page="가용성/${month%-*}년.wikitext"
  [ -e "$page" ] || [ -e "$out/$page" ] || printf '{{#invoke:Availability.lua|year|%s}}\n' "${month%-*}" > "$out/$page"
  echo "$month"
done

for f in "$out"/Module:가용성/[0-9][0-9][0-9][0-9]-[0-9][0-9].json; do
  jq -c '{month, checks: (.checks | with_entries(.value = ((.value | map(select(. != null))) as $v | if ($v | length) > 0 then {hours: ($v | length), uptime: (($v | add) / ($v | length) * 1000000 | round / 1000000)} else null end)))}' "$f"
done | jq -s 'sort_by(.month)' > "$out/Module:가용성/months.json"
