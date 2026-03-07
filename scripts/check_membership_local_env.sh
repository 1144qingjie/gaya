#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/gaya.xcodeproj"
WORKSPACE_PATH="${ROOT_DIR}/gaya.xcworkspace"
SCHEME_PATH="${PROJECT_PATH}/xcshareddata/xcschemes/gaya.xcscheme"
SECRETS_PATH="${ROOT_DIR}/gaya/Secrets.swift"
STOREKIT_DIR="${ROOT_DIR}/gaya/Resources/StoreKit"
STOREKIT_FILES=()

if [[ -d "${STOREKIT_DIR}" ]]; then
  while IFS= read -r file; do
    STOREKIT_FILES+=("${file}")
  done < <(find "${STOREKIT_DIR}" -maxdepth 1 -name '*.storekit' | sort)
fi

pass() {
  printf '[PASS] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
}

printf 'Membership local environment check\n'
printf 'root: %s\n\n' "${ROOT_DIR}"

if [[ -d "${PROJECT_PATH}" && -d "${WORKSPACE_PATH}" ]]; then
  pass "Xcode project and workspace are present"
else
  fail "Missing Xcode project or workspace"
fi

if [[ -f "${SCHEME_PATH}" ]]; then
  pass "Shared scheme exists: ${SCHEME_PATH}"
else
  fail "Shared scheme missing: ${SCHEME_PATH}"
fi

if [[ -f "${SCHEME_PATH}" ]]; then
  if rg -q 'StoreKitConfiguration' "${SCHEME_PATH}"; then
    pass "Shared scheme appears to reference a StoreKit Configuration"
  else
    warn "Shared scheme does not yet appear to reference a StoreKit Configuration"
  fi
fi

if [[ -f "${SECRETS_PATH}" ]]; then
  if rg -q '<YOUR_CLOUDBASE_HTTP_URL>' "${SECRETS_PATH}"; then
    warn "Secrets.swift still contains placeholder CloudBase URL"
  else
    pass "Secrets.swift contains a non-placeholder CloudBase URL"
  fi
else
  fail "Secrets.swift is missing"
fi

if ((${#STOREKIT_FILES[@]} > 0)); then
  pass "Found local StoreKit file(s):"
  for file in "${STOREKIT_FILES[@]}"; do
    printf '       - %s\n' "${file}"
  done
else
  warn "No .storekit file found under ${STOREKIT_DIR}"
fi

if xcodebuild -list -project "${PROJECT_PATH}" >/tmp/gaya_membership_scheme_check.txt 2>/tmp/gaya_membership_scheme_check.err; then
  if rg -q 'Schemes:\s*$|^\s*gaya$' /tmp/gaya_membership_scheme_check.txt; then
    pass "xcodebuild can see the gaya scheme"
  else
    warn "xcodebuild ran, but the output did not clearly list the gaya scheme"
  fi
else
  warn "xcodebuild -list failed; inspect /tmp/gaya_membership_scheme_check.err"
fi

printf '\nNext steps\n'
printf '1. In Xcode, create or place a .storekit file under %s\n' "${STOREKIT_DIR}"
printf '2. Edit the gaya scheme and attach that StoreKit Configuration to Run > Options\n'
printf '3. Launch the app, open the membership center, and confirm the summary card is no longer in 调试模拟 mode\n'
printf '4. In DEBUG builds, verify the 订阅调试 panel shows 商品状态=已就绪 and 计费模式=App Store 真实订阅\n'
