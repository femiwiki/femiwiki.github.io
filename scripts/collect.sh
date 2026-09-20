#!/usr/bin/env bash
set -euo pipefail
out=$1
closed=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
if [ $# -ge 2 ]; then
  [[ "$2" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { echo "month must be YYYY-MM, got '$2'" >&2; exit 2; }
  months=("$2")
else
  months=("$(date -u -d "$closed-01 -1 day" +%Y-%m)" "$closed")
fi
account=$(aws sts get-caller-identity --query Account --output text)
mkdir -p "$out/Module:비용" "$out/비용"
credits=$(aws billing get-credits --output json --region us-east-1 --account-id "$account" --start-date 2020-01-01)

next_month() { date -u -d "$1-01 +1 month" +%Y-%m; }
active() { jq -r --arg m "$1" '.credits[] | select(.startDate[:7] <= $m and .endDate[:7] >= $m) | .creditId' <<< "$credits"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch_invoice() {
  aws invoicing list-invoice-summaries --output json --region us-east-1 \
    --selector "ResourceType=ACCOUNT_ID,Value=$account" \
    --filter "{\"BillingPeriod\":{\"Year\":${1%-*},\"Month\":$((10#${1#*-}))}}"
}
strip_invoice() {
  jq --sort-keys 'del(.InvoiceSummaries[].InvoiceId, .InvoiceSummaries[].AccountId, .InvoiceSummaries[].BillSourceAccounts)'
}
invoice() {
  local f="$out/Module:비용/$1/invoice.json"
  [ -e "$f" ] || f="$tmp/$1-invoice.json"
  [ -e "$f" ] || fetch_invoice "$1" | strip_invoice > "$f"
  cat "$f"
}

# One call answers for the billing month holding --end-date alone; its first page is complete while
# nextToken repeats rows, so never paginate; and about one call in five returns nothing, so retry.
applied() {
  local n wait
  for wait in 1 2 3 4 0; do
    n=$(aws billing get-credit-allocation-history --output json --region us-east-1 --account-id "$account" \
      --credit-id "$1" --start-date "$2-01" --end-date "$(date -u -d "$2-01 +1 month -1 day" +%Y-%m-%d)" \
      --no-paginate --max-results 1000 \
      | jq '[.creditAllocationHistoryList[] | select(.isEstimatedBill | not) | .creditAmount.currencyAmount | tonumber] | add // 0')
    [ "$n" != 0 ] && break
    sleep "$wait"
  done
  echo "$n"
}

declare -A used
for month in "${months[@]}"; do
  dir="$out/Module:비용/$month"
  mkdir -p "$dir"
  # Cost Explorer keeps 37 months; an older month has its bill.json, captured from the
  # console by hand (issue #30), and the invoice. Grouping by record type is what tells
  # usage from credits and tax: UnblendedCost alone has both folded in.
  if ! aws ce get-cost-and-usage --output json \
    --time-period "Start=$month-01,End=$(date -u -d "$month-01 +1 month" +%Y-%m-%d)" \
    --granularity MONTHLY --metrics UnblendedCost \
    --group-by Type=DIMENSION,Key=SERVICE Type=DIMENSION,Key=RECORD_TYPE 2> "$tmp/ce.err" \
    | jq --sort-keys . > "$dir/cost.json"; then
    grep -q 'maximum data available' "$tmp/ce.err" || { cat "$tmp/ce.err" >&2; exit 1; }
    rm -f "$dir/cost.json"
  fi
  rm -f "$dir/invoice.json" "$tmp/$month-invoice.json"
  raw=$(fetch_invoice "$month")
  strip_invoice <<< "$raw" > "$dir/invoice.json"
  id=$(jq -r '.InvoiceSummaries[0].InvoiceId // empty' <<< "$raw")
  if [ -n "$id" ]; then
    curl -fsSL -o "$tmp/$month.pdf" \
      "$(aws invoicing get-invoice-pdf --output json --region us-east-1 --invoice-id "$id" | jq -r '.InvoicePDF.DocumentUrl')"
    "$(dirname "$0")/redact-address.sh" "$tmp/$month.pdf" "$out/비용/$month.pdf"
  fi

  # Only the latest month's credit snapshot is shown, so only that one is computed.
  [ "$month" = "$closed" ] || continue
  after='{}'
  m=$(next_month "$month")
  while [[ "$m" < "$closed" || "$m" == "$closed" ]]; do
    total=0
    for id in $(active "$m"); do
      [ -n "${used[$id:$m]+x}" ] || used[$id:$m]=$(applied "$id" "$m")
      total=$(jq -n --argjson a "$total" --argjson b "${used[$id:$m]}" '$a + $b')
      after=$(jq --arg id "$id" --argjson s "${used[$id:$m]}" '.[$id] = ((.[$id] // 0) + $s)' <<< "$after")
    done
    billed=$(invoice "$m" | jq '[.InvoiceSummaries[0].BaseCurrencyAmount.AmountBreakdown.Discounts.Breakdown // [] | .[] | select(.Description == "Credits") | .Amount | tonumber] | add // 0')
    jq -en --argjson a "$total" --argjson b "$billed" '($a + $b) | fabs < 0.5' > /dev/null \
      || { echo "credit allocations for $m sum to $total but the invoice says $billed" >&2; exit 1; }
    m=$(next_month "$m")
  done
  jq --sort-keys --arg m "$month" --argjson after "$after" '
    [.credits[] | select(.startDate[:7] <= $m and .endDate[:7] >= $m)
     | . + {closingAmount: ((.remainingAmount.currencyAmount | tonumber) - ($after[.creditId] // 0))}
     | del(.creditId, .accountId, .shareableAccounts, .applicableProductNames, .estimatedAmount, .remainingAmount)]' \
    <<< "$credits" > "$dir/credits.json"

done
# One file with every month's totals, so the status page loads one page and not two per
# month. Usage is before credits and tax; the bill from the console is preferred, since
# it is the same shape for every month back to 2016.
for d in "$out"/Module:비용/[0-9][0-9][0-9][0-9]-[0-9][0-9]/; do
  m=$(basename "$d")
  printf '{{#invoke:Cost.lua|month|%s}}\n' "$m" > "$out/비용/$m.wikitext"
  if [ -e "$d/bill.json" ]; then
    figures=$(jq '
      ([.services[].regions[].groups[].items[] | select(.type != "Credit") | .amount] | add // 0) as $usage
      | ([.services[].amount] | add // 0) as $net
      | {usage: $usage, credits: ($net - $usage), tax: (.total - $net), total}' "$d/bill.json")
  elif [ -e "$d/cost.json" ]; then
    figures=$(jq '
      [.ResultsByTime[0].Groups[] | {type: .Keys[1], amount: (.Metrics.UnblendedCost.Amount | tonumber)}]
      | (map(select(.type == "Credit" or .type == "Refund") | .amount) | add // 0) as $credits
      | (map(select(.type == "Tax") | .amount) | add // 0) as $tax
      | (map(select(.type != "Credit" and .type != "Refund" and .type != "Tax") | .amount) | add // 0) as $usage
      | {usage: $usage, credits: $credits, tax: $tax, total: ($usage + $credits + $tax)}' "$d/cost.json")
  else
    figures='{}'
  fi
  jq -n --arg month "$m" --argjson figures "$figures" --argjson invoice "$(cat "$d/invoice.json")" '
    ($invoice.InvoiceSummaries[0].PaymentCurrencyAmount) as $pay
    | {month: $month} + $figures
      + (if $pay then {billed: ($pay.TotalAmount | tonumber), currency: $pay.CurrencyCode}
          + (if $pay.CurrencyExchangeDetails then {rate: $pay.CurrencyExchangeDetails.Rate} else {} end)
        else {} end)'
done | jq -s 'sort_by(.month)' > "$out/Module:비용/months.json"
