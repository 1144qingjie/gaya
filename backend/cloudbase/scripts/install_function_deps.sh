#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for fn in auth_db_init auth_onetap_login auth_sms_send auth_sms_verify user_bootstrap; do
  echo "Installing dependencies for ${fn} ..."
  (cd "${ROOT_DIR}/functions/${fn}" && npm install)
done

echo "All function dependencies installed."
