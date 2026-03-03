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

if [[ -z "${AUTH_API_BASE_URL:-}" ]]; then
  echo "Missing required env var: AUTH_API_BASE_URL"
  echo "Example: AUTH_API_BASE_URL=https://<your-domain>.ap-shanghai.app.tcloudbase.com"
  exit 1
fi

BASE_URL="${AUTH_API_BASE_URL%/}"

echo "Smoke testing auth HTTP routes with base URL: ${BASE_URL}"

post_json() {
  local path="$1"
  local body="$2"
  curl -sS -X POST "${BASE_URL}${path}" \
    -H 'content-type: application/json' \
    -H 'x-device-id:smoke-device' \
    -d "${body}"
}

assert_contains() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "${actual}" != *"${expected}"* ]]; then
    echo "[FAIL] ${name}"
    echo "Expected to contain: ${expected}"
    echo "Actual: ${actual}"
    exit 1
  fi
  echo "[PASS] ${name}"
}

assert_not_contains() {
  local name="$1"
  local actual="$2"
  local unexpected="$3"
  if [[ "${actual}" == *"${unexpected}"* ]]; then
    echo "[FAIL] ${name}"
    echo "Unexpected content: ${unexpected}"
    echo "Actual: ${actual}"
    exit 1
  fi
  echo "[PASS] ${name}"
}

r1="$(post_json '/auth/onetap/login' '{"agreement_accepted":true}')"
assert_contains "route /auth/onetap/login" "${r1}" "缺少一键登录 token"

r_sms_send="$(post_json '/auth/sms/send' '{"agreement_accepted":true,"phone_number":"13800138000"}')"
assert_not_contains "route /auth/sms/send reachable" "${r_sms_send}" "INVALID_PATH"
assert_not_contains "route /auth/sms/send activated" "${r_sms_send}" "HTTPSERVICE_NONACTIVATED"

r2="$(post_json '/user/bootstrap' '{"nickname":"smoke"}')"
assert_contains "route /user/bootstrap" "${r2}" "缺少 uid"

r3="$(post_json '/auth/sms/verify' '{"agreement_accepted":true,"phone_number":"13800138000","verify_code":"123456","challenge_id":"non-existent"}')"
assert_contains "route /auth/sms/verify" "${r3}" "验证码会话不存在"

echo "All smoke checks passed."
