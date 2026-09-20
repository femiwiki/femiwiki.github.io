#!/usr/bin/env bash
set -euo pipefail
out=$1
closed=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
if [ $# -ge 2 ]; then
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
invoice() {
  local f="$out/Module:비용/$1/invoice.json"
  [ -e "$f" ] || f="$tmp/$1-invoice.json"
  [ -e "$f" ] || aws invoicing list-invoice-summaries --output json --region us-east-1 \
    --selector "ResourceType=ACCOUNT_ID,Value=$account" \
    --filter "{\"BillingPeriod\":{\"Year\":${1%-*},\"Month\":$((10#${1#*-}))}}" \
    | jq --sort-keys 'del(.InvoiceSummaries[].InvoiceId, .InvoiceSummaries[].AccountId, .InvoiceSummaries[].BillSourceAccounts)' \
    > "$f"
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
  aws ce get-cost-and-usage --output json \
    --time-period "Start=$month-01,End=$(date -u -d "$month-01 +1 month" +%Y-%m-%d)" \
    --granularity MONTHLY --metrics UnblendedCost NetUnblendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    | jq --sort-keys . > "$dir/cost.json"
  rm -f "$dir/invoice.json" "$tmp/$month-invoice.json"
  invoice "$month" > /dev/null
  mv "$tmp/$month-invoice.json" "$dir/invoice.json"

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
    jq -en --argjson a "$total" --argjson b "$billed" '($a + $b) | fabs < 0.01' > /dev/null \
      || { echo "credit allocations for $m sum to $total but the invoice says $billed" >&2; exit 1; }
    m=$(next_month "$m")
  done
  jq --sort-keys --arg m "$month" --argjson after "$after" '
    [.credits[] | select(.startDate[:7] <= $m and .endDate[:7] >= $m)
     | . + {closingAmount: ((.remainingAmount.currencyAmount | tonumber) - ($after[.creditId] // 0))}
     | del(.creditId, .accountId, .shareableAccounts, .applicableProductNames, .estimatedAmount, .remainingAmount)]' \
    <<< "$credits" > "$dir/credits.json"

  printf '{{#invoke:비용/표.lua|월|%s}}\n' "$month" > "$out/비용/$month.wikitext"
done
for d in "$out"/Module:비용/[0-9][0-9][0-9][0-9]-[0-9][0-9]/; do basename "$d"; done | sort | jq -R . | jq -s . > "$out/Module:비용/months.json"
