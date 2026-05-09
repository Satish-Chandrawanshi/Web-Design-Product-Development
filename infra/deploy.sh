#!/usr/bin/env bash
# Convenience wrapper around `fly deploy`. Run from the repo root.
#
#   ./infra/deploy.sh           # rolling deploy of api + worker
#   ./infra/deploy.sh --build-only
#
# Prereqs: a Fly app named per `infra/fly.toml`, a Postgres cluster
# attached, and the secrets listed in fly.toml's header.
set -euo pipefail

cd "$(dirname "$0")/.."

FLY_APP="${FLY_APP:-reminder-backend}"

if [[ "${1:-}" == "--build-only" ]]; then
    fly image build --app "$FLY_APP" --config infra/fly.toml --dockerfile infra/Dockerfile .
    exit 0
fi

fly deploy --app "$FLY_APP" --config infra/fly.toml --dockerfile infra/Dockerfile .
fly status --app "$FLY_APP"
