#!/usr/bin/env bash
# Hourly host metrics, one file per month: Module:호스트/YYYY-MM.json holds, per host, what
# CloudWatch has for its instance and each of its volumes, one value per hour of the
# month in Seoul time (null where there is no data). CloudWatch drops them after 15
# months, and they were all that was left to read the December 2025 outage with.
# Nothing renders this; it is kept so the next outage can be explained.
set -euo pipefail
out=$1
closed=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
if [ $# -ge 2 ]; then
  [[ "$2" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { echo "month must be YYYY-MM, got '$2'" >&2; exit 2; }
  months=("$2")
else
  months=("$(date -u -d "$closed-01 -1 day" +%Y-%m)" "$closed")
fi
mkdir -p "$out/Module:호스트"

# A host is known by its Name tag and lists its instance and its volumes by device.
# Replacing an instance gives it a new ID and CloudWatch keeps the old one's metrics
# for the rest of the 15 months, so retired hosts stay listed here; a host whose
# month is empty is left out of that month's file. "femiwiki" was the single box that
# ran everything until the 2025-08-30 rebuild into "docker" and "database".
hosts='{"femiwiki": {"instance": "i-0cf3c535463ebf083", "volumes": {"/dev/xvda": "vol-06763fd49d74b6b19", "/dev/sdb": "vol-046c6026dc27a61de"}}}'
hosts=$(aws ec2 describe-instances --output json --filters Name=tag-key,Values=Name \
  | jq --argjson known "$hosts" '$known + ([.Reservations[].Instances[]
      | {key: (.Tags[] | select(.Key == "Name") | .Value),
         value: {instance: .InstanceId, volumes: ([.BlockDeviceMappings[] | {key: .DeviceName, value: .Ebs.VolumeId}] | from_entries)}}]
      | from_entries)')

# What each metric's hourly value is: a level is averaged, a count is summed, and a
# status check that failed at any point in the hour marks the hour.
stats='{"CPUUtilization": "Average", "CPUCreditBalance": "Average", "CPUSurplusCreditsCharged": "Sum", "StatusCheckFailed": "Maximum",
  "NetworkIn": "Sum", "NetworkOut": "Sum", "VolumeReadBytes": "Sum", "VolumeWriteBytes": "Sum"}'

queries() { # -> metric data queries for every host's instance and volumes, labelled host|device|metric
  jq -c --argjson stats "$stats" '
    def q($label; $ns; $dim; $id; $metric): {Label: $label, MetricStat: {Metric: {Namespace: $ns, MetricName: $metric, Dimensions: [{Name: $dim, Value: $id}]}, Period: 3600, Stat: $stats[$metric]}};
    [to_entries[] | .key as $host | .value as $h
      | (("CPUUtilization", "CPUCreditBalance", "CPUSurplusCreditsCharged", "StatusCheckFailed", "NetworkIn", "NetworkOut")
          | q("\($host)||\(.)"; "AWS/EC2"; "InstanceId"; $h.instance; .)),
        ($h.volumes | to_entries[] | .key as $dev | .value as $vol
          | ("VolumeReadBytes", "VolumeWriteBytes") | q("\($host)|\($dev)|\(.)"; "AWS/EBS"; "VolumeId"; $vol; .))]
    | to_entries | map(.value + {Id: "q\(.key)"})' <<< "$hosts"
}

# A month runs from midnight to midnight in Seoul, like the availability files.
for month in "${months[@]}"; do
  start=$(date -u -d "$month-01T00:00:00+09:00" +%Y-%m-%dT%H:%M:%SZ)
  end=$(date -u -d "$(date -u -d "$month-01 +1 month" +%Y-%m-01)T00:00:00+09:00" +%Y-%m-%dT%H:%M:%SZ)
  TZ=UTC aws cloudwatch get-metric-data --output json \
    --start-time "$start" --end-time "$end" --metric-data-queries "$(queries)" \
    | jq --compact-output --sort-keys --arg month "$month" --arg start "$start" --arg end "$end" --argjson hosts "$hosts" --argjson stats "$stats" '
      def hour: (. | sub("\\+00:00$"; "Z") | fromdateiso8601 - ($start | fromdateiso8601)) / 3600 | floor;
      # Percentages and credits keep two decimals; bytes and counts are whole.
      def tidy($metric): if $metric | test("^CPU(Utilization|CreditBalance)$") then . * 100 | round / 100 else round end;
      (($end | fromdateiso8601) - ($start | fromdateiso8601)) / 3600 as $hours
      | [.MetricDataResults[] | (.Label | split("|")) as [$host, $dev, $metric]
          | ([.Timestamps, .Values] | transpose | map({key: (.[0] | hour | tostring), value: .[1]}) | from_entries) as $by
          | {host: $host, dev: $dev, metric: $metric, values: [range($hours) | tostring | if $by[.] != null then ($by[.] | tidy($metric)) else null end]}]
      | map(select(.values | any(. != null)))
      | group_by(.host)
      | map({
          key: .[0].host,
          value: (
            .[0].host as $host
            | {instance: $hosts[$host].instance,
               metrics: (map(select(.dev == "")) | map({key: .metric, value: .values}) | from_entries),
               volumes: (map(select(.dev != "")) | group_by(.dev)
                 | map({key: .[0].dev, value: {id: $hosts[$host].volumes[.[0].dev], metrics: (map({key: .metric, value: .values}) | from_entries)}}) | from_entries)})})
      | from_entries
      | {month: $month, hours: $hours, stats: $stats, hosts: .}' > "$out/Module:호스트/$month.json"
  echo "$month"
done
