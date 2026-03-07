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

required_vars=(
  TCB_ENV
  TENCENTCLOUD_SECRETID
  TENCENTCLOUD_SECRETKEY
  APP_JWT_SECRET
  ACCESS_TOKEN_EXPIRES_IN
  REFRESH_TOKEN_EXPIRES_IN
  ALIYUN_ACCESS_KEY_ID
  ALIYUN_ACCESS_KEY_SECRET
  PNVS_SMS_SIGN_NAME
  PNVS_SMS_TEMPLATE_CODE
)

for key in "${required_vars[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: ${key}"
    exit 1
  fi
done

run_tcb() {
  npx tcb "$@"
}

FUNCTIONS=(
  auth_db_init
  auth_onetap_login
  auth_sms_send
  auth_sms_verify
  user_bootstrap
  membership_profile_get
  membership_products_list
  membership_purchase_sync
  membership_restore_sync
  membership_hold_create
  membership_hold_commit
  membership_hold_release
  membership_ledger_list
)

route_points_to_target() {
  local service_path="$1"
  local function_name="$2"
  local list_output
  list_output="$(run_tcb service list -e "${TCB_ENV}" 2>/dev/null || true)"

  if echo "${list_output}" | grep -F "${service_path}" | grep -Fq "${function_name}"; then
    return 0
  fi

  return 1
}

echo "Syncing shared common modules into each function package..."
bash "${ROOT_DIR}/scripts/sync_common_to_functions.sh"

echo "Logging into Tencent Cloud..."
run_tcb login -k --apiKeyId "${TENCENTCLOUD_SECRETID}" --apiKey "${TENCENTCLOUD_SECRETKEY}"

echo "Deploying functions sequentially to avoid CloudBase queue mis-packaging ..."
for fn in "${FUNCTIONS[@]}"; do
  echo "Deploying function: ${fn}"
  run_tcb fn deploy "${fn}" -e "${TCB_ENV}" --force
  echo "Updating function config: ${fn}"
  run_tcb fn config update "${fn}" -e "${TCB_ENV}"
done

upsert_service_route() {
  local raw_path="$1"
  local function_name="$2"
  local service_path

  if [[ "${raw_path}" == /* ]]; then
    service_path="${raw_path}"
  else
    service_path="/${raw_path}"
  fi

  # Clear both legacy path format (without leading slash) and canonical format.
  run_tcb service delete -e "${TCB_ENV}" -p "${service_path}" >/dev/null 2>&1 || true
  if [[ "${raw_path}" != "${service_path}" ]]; then
    run_tcb service delete -e "${TCB_ENV}" -p "${raw_path}" >/dev/null 2>&1 || true
  fi

  if run_tcb service create -e "${TCB_ENV}" -p "${service_path}" -f "${function_name}"; then
    return 0
  fi

  if route_points_to_target "${service_path}" "${function_name}"; then
    echo "Route already exists and points to ${function_name}: ${service_path}"
    return 0
  fi

  echo "Retrying route create after cleanup: ${service_path}"
  run_tcb service delete -e "${TCB_ENV}" -p "${service_path}" >/dev/null 2>&1 || true
  sleep 2

  if run_tcb service create -e "${TCB_ENV}" -p "${service_path}" -f "${function_name}"; then
    return 0
  fi

  if route_points_to_target "${service_path}" "${function_name}"; then
    echo "Route became available and points to ${function_name}: ${service_path}"
    return 0
  fi

  echo "Failed to upsert route: ${service_path} -> ${function_name}"
  return 1
}

echo "Binding HTTP routes..."
upsert_service_route "/auth/onetap/login" "auth_onetap_login"
upsert_service_route "/auth/sms/send" "auth_sms_send"
upsert_service_route "/auth/sms/verify" "auth_sms_verify"
upsert_service_route "/user/bootstrap" "user_bootstrap"
upsert_service_route "/membership/profile" "membership_profile_get"
upsert_service_route "/membership/products" "membership_products_list"
upsert_service_route "/membership/purchase/sync" "membership_purchase_sync"
upsert_service_route "/membership/restore/sync" "membership_restore_sync"
upsert_service_route "/membership/hold/create" "membership_hold_create"
upsert_service_route "/membership/hold/commit" "membership_hold_commit"
upsert_service_route "/membership/hold/release" "membership_hold_release"
upsert_service_route "/membership/ledger/list" "membership_ledger_list"

echo "Current HTTP service routes:"
run_tcb service list -e "${TCB_ENV}" || true

echo
echo "Deploy completed. Configure iOS AUTH_API_BASE_URL using your CloudBase HTTP domain."
