#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -f "${ROOT_DIR}/.env.deploy" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env.deploy"
  set +a
fi

if [[ -z "${TCB_ENV:-}" ]]; then
  echo "Missing required env var: TCB_ENV"
  exit 1
fi

if [[ ! -d "${ROOT_DIR}/functions/auth_db_init" ]]; then
  echo "Missing function directory: functions/auth_db_init"
  exit 1
fi

echo "Syncing shared common modules..."
bash "${ROOT_DIR}/scripts/sync_common_to_functions.sh"

echo "Installing dependencies for auth_db_init..."
(cd "${ROOT_DIR}/functions/auth_db_init" && npm install)

echo "Deploying auth_db_init..."
npx tcb fn deploy auth_db_init -e "${TCB_ENV}" --force

echo "Invoking auth_db_init..."
TMP_OUT="$(mktemp)"
npx tcb fn invoke auth_db_init -e "${TCB_ENV}" --params '{}' | tee "${TMP_OUT}"

if ! rg -q 'Return result：\{"code":0' "${TMP_OUT}"; then
  echo "DB initialization failed: auth_db_init returned non-zero business code"
  rm -f "${TMP_OUT}"
  exit 1
fi
rm -f "${TMP_OUT}"

echo "DB initialization completed."
