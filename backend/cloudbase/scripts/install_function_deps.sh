#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for fn in auth_db_init auth_onetap_login auth_sms_send auth_sms_verify user_bootstrap membership_profile_get membership_products_list membership_purchase_sync membership_restore_sync membership_hold_create membership_hold_commit membership_hold_release membership_ledger_list; do
  echo "Installing dependencies for ${fn} ..."
  (cd "${ROOT_DIR}/functions/${fn}" && npm install)
done

echo "All function dependencies installed."
