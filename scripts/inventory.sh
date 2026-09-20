#!/usr/bin/env bash
# Lists the org's public repositories, what kinds of files each holds and which
# formatters and linters its CI runs on them. Writes Module:린트/inventory.json
# under the given directory. Needs gh with a token that can read public repos.
set -euo pipefail

out=$1
org=femiwiki
mkdir -p "$out/Module:린트"

# tool;pattern;kinds it covers
tools='prettier;prettier;js css json yaml md
biome;biome;js css json
eslint;eslint;js
stylelint;stylelint;css
banana;banana;json
phpcs;phpcs;php
php-cs-fixer;php-cs-fixer;php
parallel-lint;parallel-lint;php
phan;phan;php
black;black;py
ruff;ruff;py
flake8;flake8;py
isort;isort;py
gofmt;gofmt|go fmt;go
golangci-lint;golangci;go
go vet;go vet;go
terraform fmt;terraform fmt;tf
tflint;tflint;tf
shellcheck;shellcheck;sh
shfmt;shfmt;sh
stylua;stylua;lua
luacheck;luacheck;lua
hadolint;hadolint;dockerfile
yamllint;yamllint;yaml
rumdl;rumdl;md
markdownlint;markdownlint;md
taplo;taplo;toml'

fetch() { # repo path [ref]
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/$org/$1/contents/$2${3:+?ref=$3}" 2>/dev/null || true
}

# Everything CI could run: the workflows, the reusable workflows they call, and
# the package scripts they hand off to.
ci_text() { # repo tree-json
  local text wf other rest path
  text=$(for wf in $(jq -r '.[] | select(test("^\\.github/workflows/[^/]+\\.ya?ml$"))' <<<"$2"); do fetch "$1" "$wf"; done)
  while read -r other; do
    rest=${other#*/} path=${rest#*/}
    text+=$'\n'$(gh api -H 'Accept: application/vnd.github.raw+json' "repos/${other%%/*}/${rest%%/*}/contents/${path%@*}?ref=${other##*@}" 2>/dev/null || true)
  done < <(grep -oE 'uses: *[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[^@ ]+@[^ ]+' <<<"$text" | sed 's/uses: *//' | sort -u)
  if grep -qE 'npm|yarn|composer|grunt|quibble' <<<"$text"; then
    for other in package.json composer.json Gruntfile.js; do
      jq -e --arg f "$other" 'index($f)' <<<"$2" >/dev/null && text+=$'\n'$(fetch "$1" "$other")
    done
  fi
  printf '%s' "$text"
}

detect() { # text -> json {kind: [tools]}
  local name pattern kinds
  while IFS=';' read -r name pattern kinds; do
    if grep -qiE "(^|[^[:alnum:]_])(${pattern})([^[:alnum:]_]|$)" <<<"$1"; then
      for k in $kinds; do printf '{"kind":"%s","tool":"%s"}\n' "$k" "$name"; done
    fi
  done <<<"$tools" | jq -s 'group_by(.kind) | map({key: .[0].kind, value: map(.tool)}) | from_entries'
}

count_kinds() { # tree-json -> json {kind: files}
  jq '
    def kind:
      if test("(^|/)Dockerfile[^/]*$") then "dockerfile"
      elif test("\\.tf$") then "tf"
      elif test("\\.go$") then "go"
      elif test("\\.py$") then "py"
      elif test("\\.php$") then "php"
      elif test("\\.(js|mjs|cjs|ts|vue)$") then "js"
      elif test("\\.(css|less|scss)$") then "css"
      elif test("\\.json$") then "json"
      elif test("\\.ya?ml$") then "yaml"
      elif test("\\.md$") then "md"
      elif test("\\.(sh|bash)$") then "sh"
      elif test("\\.lua$") then "lua"
      elif test("\\.toml$") then "toml"
      else empty end;
    map(select(test("^(vendor|node_modules)/|(^|/)i18n/") | not) | kind)
    | group_by(.) | map({key: .[0], value: length}) | from_entries' <<<"$1"
}

repos=$(gh repo list "$org" --visibility public --no-archived --limit 100 --json name,isFork --jq '.[] | select(.isFork | not) | .name' | sort)
for r in $repos; do
  echo "$r" >&2
  tree=$(gh api "repos/$org/$r/git/trees/HEAD?recursive=1" --jq '[.tree[] | select(.type == "blob") | .path]' 2>/dev/null || echo '[]')
  jq -n --arg name "$r" --argjson files "$(count_kinds "$tree")" --argjson tools "$(detect "$(ci_text "$r" "$tree")")" \
    '{name: $name, kinds: ($files | with_entries(.value = {files: .value, tools: ($tools[.key] // [])}))}'
done | jq -s --arg date "$(date -u +%Y-%m-%d)" '{generated: $date, repos: .}' > "$out/Module:린트/inventory.json"
