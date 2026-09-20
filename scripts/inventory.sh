#!/usr/bin/env bash
# Lists the org's public repositories, what kinds of files each holds, which
# formatters and linters its CI runs on them, and whether the job running each
# is a status check the default branch requires. Writes
# Module:린트/inventory.json under the given directory. Needs gh with a token
# that can read public repos.
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

# The status checks the default branch requires. Public, so no admin token.
required_checks() { # repo
  local branch
  branch=$(gh api "repos/$org/$1" --jq .default_branch 2>/dev/null || echo main)
  gh api "repos/$org/$1/branches/$branch" --jq '.protection.required_status_checks.contexts // []' 2>/dev/null || echo '[]'
}

# One line per job CI runs, as "context<TAB>text": the name GitHub reports the
# job under, and the job's id and YAML with the package scripts it hands off to
# appended. Jobs that call a reusable workflow expand to that workflow's jobs
# under "caller / callee".
jobs() { # repo tree-json
  local wf packages='' other
  for other in package.json composer.json Gruntfile.js; do
    if jq -e --arg f "$other" 'index($f)' <<<"$2" >/dev/null; then
      packages+=$'\n'$(fetch "$1" "$other")
    fi
  done
  for wf in $(jq -r '.[] | select(test("^\\.github/workflows/[^/]+\\.ya?ml$"))' <<<"$2"); do
    workflow_jobs "$1" "$(fetch "$1" "$wf")" '' "$packages"
  done
}

workflow_jobs() { # repo yaml prefix packages
  local json job context uses text rest path
  json=$(yq -o=json '.' <<<"$2" 2>/dev/null || true)
  for job in $(jq -r '.jobs // {} | keys_unsorted[]' <<<"$json"); do
    context=$3$(jq -r --arg j "$job" '.jobs[$j].name // $j' <<<"$json")
    uses=$(jq -r --arg j "$job" '.jobs[$j].uses // ""' <<<"$json")
    if [[ $uses == */.github/workflows/* ]]; then
      if [[ $uses == ./* ]]; then
        text=$(fetch "$1" "${uses#./}")
      else
        rest=${uses#*/} path=${rest#*/}
        text=$(gh api -H 'Accept: application/vnd.github.raw+json' "repos/${uses%%/*}/${rest%%/*}/contents/${path%@*}?ref=${uses##*@}" 2>/dev/null || true)
      fi
      workflow_jobs "$1" "$text" "$context / " "$4"
      continue
    fi
    text=$job$'\n'$(yq ".jobs[\"$job\"]" <<<"$2" 2>/dev/null || true)
    grep -qE 'npm|yarn|composer|grunt|quibble' <<<"$text" && text+=$4
    printf '%s\t%s\n' "$context" "$(tr '\n\t' '  ' <<<"$text")"
  done
}

# A job is required when its context is required outright, or as a matrix
# entry like "test (REL1_43, phan)".
is_required() { # context contexts-json
  jq -e --arg c "$1" 'any(. == $c or startswith($c + " ("))' <<<"$2" >/dev/null
}

detect() { # jobs-lines contexts-json -> json {kind: [{name, required}]}
  local context text name pattern kinds required i
  while IFS=$'\t' read -r context text; do
    required=false
    is_required "$context" "$2" && required=true
    i=0
    while IFS=';' read -r name pattern kinds; do
      i=$((i + 1))
      if grep -qiE "(^|[^[:alnum:]_])(${pattern})([^[:alnum:]_]|$)" <<<"$text"; then
        for k in $kinds; do printf '{"kind":"%s","tool":"%s","i":%d,"required":%s}\n' "$k" "$name" "$i" "$required"; done
      fi
    done <<<"$tools"
  done <<<"$1" | jq -s '
    group_by(.kind)
    | map({key: .[0].kind, value: (group_by(.i) | map({name: .[0].tool, required: any(.[]; .required)}))})
    | from_entries'
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
for repo in $repos; do
  echo "$repo" >&2
  tree=$(gh api "repos/$org/$repo/git/trees/HEAD?recursive=1" --jq '[.tree[] | select(.type == "blob") | .path]' 2>/dev/null || echo '[]')
  jq -n --arg name "$repo" --argjson files "$(count_kinds "$tree")" \
    --argjson tools "$(detect "$(jobs "$repo" "$tree")" "$(required_checks "$repo")")" \
    '{name: $name, kinds: ($files | with_entries(.value = {files: .value, tools: ($tools[.key] // [])}))}'
done | jq -s --arg date "$(date -u +%Y-%m-%d)" '{generated: $date, repos: .}' > "$out/Module:린트/inventory.json"
