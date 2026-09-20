#!/usr/bin/env bash
# The month's bill from the Data Exports file in S3, in the shape the console's
# complete bill had (issue #30), so the month page draws it the same way:
# services, each by region, each by product family, down to the line items.
# Prints nothing and exits 3 when the export has no file for the month yet.
set -euo pipefail
out=$1
month=$2
bucket="cost-exports-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 0)-ap-northeast-1-an"
prefix="cost-and-usage/femiwiki-cost-and-usage/data/BILLING_PERIOD=$month/"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${BILL_EXPORT_DIR:-}" ]; then
  cp "$BILL_EXPORT_DIR"/*.csv.gz "$tmp/"
else
  aws s3 cp --quiet --recursive "s3://$bucket/$prefix" "$tmp/" --exclude '*' --include '*.csv.gz'
fi
ls "$tmp"/*.csv.gz > /dev/null 2>&1 || exit 3

# Service names as the console wrote them, learnt from the bills already kept; a code
# the console never showed is shown as the code.
names=$(jq -s '[.[].services[] | {key: .code, value: .name}] | from_entries' "$out"/Module:비용/*/bill.json 2>/dev/null || echo '{}')

for f in "$tmp"/*.csv.gz; do mlr --icsv --ojson --gzin cat "$f"; done | jq -s --sort-keys --argjson names "$names" '
  add
  | map({
      code: .line_item_product_code,
      type: .line_item_line_item_type,
      region: (if .product_location != "" then .product_location else "No Region" end),
      family: (if .product_product_family != "" then .product_product_family else null end),
      description: .line_item_line_item_description,
      usageType: .line_item_usage_type,
      usage: (.line_item_usage_amount | tonumber),
      unit: .pricing_unit,
      amount: (.line_item_unblended_cost | tonumber)
    })
  | (map(select(.type == "Tax") | .amount) | add // 0) as $tax
  | (map(select(.type == "Credit") | .amount) | add // 0) as $credit
  | (map(select(.type != "Tax"))) as $lines
  | {
      source: "export",
      total: (($lines | map(.amount) | add // 0) + $tax),
      credits: (-$credit),
      tax: $tax,
      services: (
        $lines | group_by(.code) | map({
          code: .[0].code,
          name: ($names[.[0].code] // .[0].code),
          amount: (map(.amount) | add),
          regions: (group_by(.region) | map({
            name: .[0].region,
            amount: (map(.amount) | add),
            groups: (group_by(.family) | map({
              name: .[0].family,
              amount: (map(.amount) | add),
              items: map({description, usageType, type, usage, unit, amount})
            }))
          }))
        }) | sort_by(-.amount)
      )
    }'
