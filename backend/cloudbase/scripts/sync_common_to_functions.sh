#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMON_DIR="${ROOT_DIR}/functions/common"

for fn in auth_db_init auth_onetap_login auth_sms_send auth_sms_verify user_bootstrap; do
  TARGET_DIR="${ROOT_DIR}/functions/${fn}/common"
  rm -rf "${TARGET_DIR}"
  cp -R "${COMMON_DIR}" "${TARGET_DIR}"
  echo "Synced common -> functions/${fn}/common"
done
