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
  AUTH_API_BASE_URL
  APP_JWT_SECRET
  TCB_ENV
)

for key in "${required_vars[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: ${key}"
    exit 1
  fi
done

BASE_URL="${AUTH_API_BASE_URL%/}"
TIMESTAMP="$(date +%s)"
USER_A_UID="smoke_membership_${TIMESTAMP}_a"
USER_B_UID="smoke_membership_${TIMESTAMP}_b"
REQUEST_A="smoke_req_${TIMESTAMP}_a"
REQUEST_B="smoke_req_${TIMESTAMP}_b"
ROOT_TX_ID="smoke_orig_${TIMESTAMP}"
LATEST_TX_ID="smoke_latest_${TIMESTAMP}"

echo "Smoke testing membership HTTP routes with base URL: ${BASE_URL}"

invoke_auth_db_init_with_users() {
  local params
  params="$(node - "$USER_A_UID" "$USER_B_UID" <<'NODE'
const uidA = process.argv[2];
const uidB = process.argv[3];
process.stdout.write(JSON.stringify({
  users_to_seed: [
    { uid: uidA, nickname: "会员联调-A", register_method: "smoke_seed" },
    { uid: uidB, nickname: "会员联调-B", register_method: "smoke_seed" }
  ]
}));
NODE
)"

  local output
  output="$(npx tcb fn invoke auth_db_init -e "${TCB_ENV}" --params "${params}" 2>&1 || true)"
  if [[ "${output}" != *'Return result：{"code":0'* && "${output}" != *'Return result: {"code":0'* ]]; then
    echo "[FAIL] auth_db_init seed users"
    echo "${output}"
    exit 1
  fi
  echo "[PASS] auth_db_init seed users"
}

json_query() {
  local json="$1"
  local path="$2"
  node - "${json}" "${path}" <<'NODE'
const json = process.argv[2];
const path = process.argv[3];

function getValue(input, rawPath) {
  const segments = rawPath
    .split(".")
    .filter(Boolean)
    .map((segment) => (/^\d+$/.test(segment) ? Number(segment) : segment));

  let current = input;
  for (const segment of segments) {
    if (current == null) {
      return undefined;
    }
    current = current[segment];
  }
  return current;
}

const parsed = JSON.parse(json);
const value = getValue(parsed, path);

if (value == null) {
  process.stdout.write("");
} else if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
NODE
}

make_access_token() {
  local uid="$1"
  node - "$uid" "${APP_JWT_SECRET}" <<'NODE'
const crypto = require("crypto");
const uid = process.argv[2];
const secret = process.argv[3];

function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

const now = Math.floor(Date.now() / 1000);
const header = { alg: "HS256", typ: "JWT" };
const payload = {
  uid,
  type: "access",
  iat: now,
  exp: now + 2 * 60 * 60,
};

const encodedHeader = base64url(JSON.stringify(header));
const encodedPayload = base64url(JSON.stringify(payload));
const signature = crypto
  .createHmac("sha256", secret)
  .update(`${encodedHeader}.${encodedPayload}`)
  .digest("base64")
  .replace(/=/g, "")
  .replace(/\+/g, "-")
  .replace(/\//g, "_");

process.stdout.write(`${encodedHeader}.${encodedPayload}.${signature}`);
NODE
}

post_json() {
  local path="$1"
  local body="$2"
  curl -sS -X POST "${BASE_URL}${path}" \
    -H 'content-type: application/json' \
    -H 'x-device-id:smoke-device' \
    -d "${body}"
}

post_auth_json() {
  local path="$1"
  local token="$2"
  local body="$3"
  curl -sS -X POST "${BASE_URL}${path}" \
    -H 'content-type: application/json' \
    -H 'x-device-id:smoke-device' \
    -H "authorization: Bearer ${token}" \
    -d "${body}"
}

assert_eq() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "[FAIL] ${name}"
    echo "Expected: ${expected}"
    echo "Actual: ${actual}"
    exit 1
  fi
  echo "[PASS] ${name}"
}

assert_nonempty() {
  local name="$1"
  local actual="$2"
  if [[ -z "${actual}" ]]; then
    echo "[FAIL] ${name}"
    echo "Expected non-empty value"
    exit 1
  fi
  echo "[PASS] ${name}"
}

assert_number_ge() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ -z "${actual}" ]] || ! [[ "${actual}" =~ ^-?[0-9]+$ ]]; then
    echo "[FAIL] ${name}"
    echo "Expected integer >= ${expected}, actual: ${actual}"
    exit 1
  fi
  if (( actual < expected )); then
    echo "[FAIL] ${name}"
    echo "Expected integer >= ${expected}, actual: ${actual}"
    exit 1
  fi
  echo "[PASS] ${name}"
}

invoke_auth_db_init_with_users

ACCESS_TOKEN_A="$(make_access_token "${USER_A_UID}")"
ACCESS_TOKEN_B="$(make_access_token "${USER_B_UID}")"

products_response="$(post_json '/membership/products' '{}')"
assert_eq "membership products code" "$(json_query "${products_response}" "code")" "0"
assert_eq "membership products first plan" "$(json_query "${products_response}" "data.plans.0.plan_id")" "monthly"
assert_eq "membership products second plan" "$(json_query "${products_response}" "data.plans.1.plan_id")" "quarterly"

profile_a_before="$(post_auth_json '/membership/profile' "${ACCESS_TOKEN_A}" '{}')"
assert_eq "membership profile before purchase code" "$(json_query "${profile_a_before}" "code")" "0"
assert_eq "membership profile before purchase role" "$(json_query "${profile_a_before}" "data.current_role")" "free"
assert_eq "membership profile daily bucket type" "$(json_query "${profile_a_before}" "data.active_bucket.bucket_type")" "free_daily"
assert_number_ge "membership profile spendable points before purchase" "$(json_query "${profile_a_before}" "data.spendable_points")" 1

hold_create_release_response="$(post_auth_json '/membership/hold/create' "${ACCESS_TOKEN_A}" "$(node - "$REQUEST_A" <<'NODE'
const requestID = process.argv[2];
process.stdout.write(JSON.stringify({
  feature_key: "text_chat",
  request_id: requestID,
  payload: { source: "smoke_release" }
}));
NODE
)")"
assert_eq "membership hold create for release code" "$(json_query "${hold_create_release_response}" "code")" "0"
HOLD_RELEASE_ID="$(json_query "${hold_create_release_response}" "data.hold_id")"
assert_nonempty "membership hold release id" "${HOLD_RELEASE_ID}"

hold_release_response="$(post_auth_json '/membership/hold/release' "${ACCESS_TOKEN_A}" "$(node - "$HOLD_RELEASE_ID" "$REQUEST_A" <<'NODE'
const holdID = process.argv[2];
const requestID = process.argv[3];
process.stdout.write(JSON.stringify({
  hold_id: holdID,
  request_id: requestID,
  reason: "smoke_release"
}));
NODE
)")"
assert_eq "membership hold release code" "$(json_query "${hold_release_response}" "code")" "0"

purchase_response="$(post_auth_json '/membership/purchase/sync' "${ACCESS_TOKEN_A}" "$(node - "$ROOT_TX_ID" "$LATEST_TX_ID" <<'NODE'
const originalTransactionID = process.argv[2];
const latestTransactionID = process.argv[3];
const now = new Date();
const expiresAt = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
process.stdout.write(JSON.stringify({
  plan_id: "monthly",
  product_id: "com.gaya.membership.monthly",
  original_transaction_id: originalTransactionID,
  latest_transaction_id: latestTransactionID,
  purchase_date: now.toISOString(),
  expires_at: expiresAt.toISOString(),
  auto_renew_status: true
}));
NODE
)")"
assert_eq "membership purchase sync code" "$(json_query "${purchase_response}" "code")" "0"
assert_eq "membership purchase role" "$(json_query "${purchase_response}" "data.current_role")" "membership"
assert_eq "membership purchase plan" "$(json_query "${purchase_response}" "data.current_membership.plan_id")" "monthly"
assert_eq "membership purchase active bucket type" "$(json_query "${purchase_response}" "data.active_bucket.bucket_type")" "plan_period"

hold_create_commit_response="$(post_auth_json '/membership/hold/create' "${ACCESS_TOKEN_A}" "$(node - "$REQUEST_B" <<'NODE'
const requestID = process.argv[2];
process.stdout.write(JSON.stringify({
  feature_key: "voice_conversation",
  request_id: requestID,
  payload: { source: "smoke_commit" }
}));
NODE
)")"
assert_eq "membership hold create for commit code" "$(json_query "${hold_create_commit_response}" "code")" "0"
HOLD_COMMIT_ID="$(json_query "${hold_create_commit_response}" "data.hold_id")"
assert_nonempty "membership hold commit id" "${HOLD_COMMIT_ID}"

hold_commit_response="$(post_auth_json '/membership/hold/commit' "${ACCESS_TOKEN_A}" "$(node - "$HOLD_COMMIT_ID" "$REQUEST_B" <<'NODE'
const holdID = process.argv[2];
const requestID = process.argv[3];
process.stdout.write(JSON.stringify({
  hold_id: holdID,
  request_id: requestID,
  actual_usage: {
    billable_seconds: 65
  },
  payload: {
    source: "smoke_commit"
  }
}));
NODE
)")"
assert_eq "membership hold commit code" "$(json_query "${hold_commit_response}" "code")" "0"
assert_number_ge "membership hold committed points" "$(json_query "${hold_commit_response}" "data.committed_points")" 1

ledger_response="$(post_auth_json '/membership/ledger/list' "${ACCESS_TOKEN_A}" '{"limit":20}')"
assert_eq "membership ledger list code" "$(json_query "${ledger_response}" "code")" "0"
assert_number_ge "membership ledger list size" "$(json_query "${ledger_response}" "data.items.length")" 4

restore_response="$(post_auth_json '/membership/restore/sync' "${ACCESS_TOKEN_B}" "$(node - "$ROOT_TX_ID" "$LATEST_TX_ID" <<'NODE'
const originalTransactionID = process.argv[2];
const latestTransactionID = process.argv[3];
process.stdout.write(JSON.stringify({
  original_transaction_id: originalTransactionID,
  latest_transaction_id: latestTransactionID
}));
NODE
)")"
assert_eq "membership restore sync code" "$(json_query "${restore_response}" "code")" "0"
assert_eq "membership restore target role" "$(json_query "${restore_response}" "data.current_role")" "membership"
assert_eq "membership restore target plan" "$(json_query "${restore_response}" "data.current_membership.plan_id")" "monthly"

profile_a_after_restore="$(post_auth_json '/membership/profile' "${ACCESS_TOKEN_A}" '{}')"
assert_eq "membership source user role after restore" "$(json_query "${profile_a_after_restore}" "code")" "0"
assert_eq "membership source user became free after restore" "$(json_query "${profile_a_after_restore}" "data.current_role")" "free"

echo "All membership smoke checks passed."
