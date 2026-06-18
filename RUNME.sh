#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/Helpers/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ROOT/Helpers/.env"
    set +a
fi

exec bash "$ROOT/Helpers/Operations.sh" "${1:-menu}"
