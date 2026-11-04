#!/bin/sh
set -eu

if [ -z "${DOCKER_HOST:-}" ]; then
  DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
fi

case "$DOCKER_HOST" in
  unix://*|npipe://*) ;;
  *) printf '%s\n' 'Use a local Docker daemon for this development command.' >&2; exit 1 ;;
esac

export DOCKER_HOST
unset DOCKER_CONTEXT
docker_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dxcel-docker.XXXXXX")
trap 'rm -f "$docker_tmp/config.json"; rmdir "$docker_tmp" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
printf '{"auths":{}}\n' > "$docker_tmp/config.json"
export DOCKER_CONFIG="$docker_tmp"

supabase "$@"
