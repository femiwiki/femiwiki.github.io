#!/usr/bin/env bash
# Build and start Wikimedia's chart-renderer beside a bake, and print "address=<ip>" once
# it answers, for the bake to be given as host.docker.internal. The published site never
# talks to it; it only draws the charts while the pages are written.
set -euo pipefail

repository=https://gitlab.wikimedia.org/repos/mediawiki/services/chart-renderer.git
commit=543b8eec4fa9f56110f3fa3d6957c077e5dc4438
port=6284

source=$(mktemp -d)
git init --quiet "$source"
git -C "$source" fetch --quiet --depth 1 "$repository" "$commit"
git -C "$source" checkout --quiet FETCH_HEAD
docker build --quiet --tag chart-renderer "$source" > /dev/null
container=$(docker run --detach chart-renderer)
address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container")

# Up as soon as it says anything; what it makes of "/" does not matter.
for _ in $(seq 60); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$address:$port/" || true)" != 000 ]; then
    echo "address=$address"
    exit 0
  fi
  sleep 2
done
echo "chart-renderer never answered" >&2
docker logs "$container" >&2 || true
exit 1
