#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/smart_version.sh [--auto|--major|--minor|--patch] [-m "message"] [--push]

Options:
  --auto         Automatically choose bump type from change size (default).
  --major        Force MAJOR bump.
  --minor        Force MINOR bump.
  --patch        Force PATCH bump.
  -m, --message  Commit message.
  --push         Push commit and tag to origin after commit.
  -h, --help     Show this help.
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

has_changes() {
  if ! git diff --quiet; then
    return 0
  fi
  if ! git diff --cached --quiet; then
    return 0
  fi
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    return 0
  fi
  return 1
}

sanitize_int() {
  local value="${1:-0}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo 0
  fi
}

bump_mode="auto"
commit_message=""
push_after="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto|--major|--minor|--patch)
      bump_mode="${1#--}"
      shift
      ;;
    -m|--message)
      [ "$#" -ge 2 ] || fail "Missing message after $1"
      commit_message="$2"
      shift 2
      ;;
    --push)
      push_after="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not inside a git repository."

if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
  fail "Unresolved merge conflicts detected."
fi

if ! has_changes; then
  echo "No changes detected. Nothing to commit."
  exit 0
fi

git add -A

staged_files="$(git diff --cached --name-only)"
[ -n "$staged_files" ] || fail "No stageable changes found."

file_count="$(printf '%s\n' "$staged_files" | sed '/^$/d' | wc -l | tr -d ' ')"
read -r additions deletions < <(
  git diff --cached --numstat | awk '
    BEGIN { add = 0; del = 0 }
    {
      if ($1 ~ /^[0-9]+$/) add += $1;
      if ($2 ~ /^[0-9]+$/) del += $2;
    }
    END { print add, del }'
)
additions="$(sanitize_int "$additions")"
deletions="$(sanitize_int "$deletions")"
total_lines="$((additions + deletions))"

touches_core="false"
if printf '%s\n' "$staged_files" | grep -Eq '^(gaya\.xcodeproj/project\.pbxproj|Podfile|Podfile\.lock|backend/cloudbase/functions/)'; then
  touches_core="true"
fi

if [ "$bump_mode" = "auto" ]; then
  if [ "$total_lines" -ge 1000 ] || [ "$file_count" -ge 25 ]; then
    bump_mode="major"
  elif [ "$total_lines" -ge 300 ] || [ "$file_count" -ge 8 ] || { [ "$touches_core" = "true" ] && [ "$total_lines" -ge 200 ]; }; then
    bump_mode="minor"
  else
    bump_mode="patch"
  fi
fi

latest_tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"

if [ -z "$latest_tag" ]; then
  major=0
  minor=0
  patch=0
else
  version="${latest_tag#v}"
  IFS='.' read -r major minor patch <<< "$version"
  major="$(sanitize_int "$major")"
  minor="$(sanitize_int "$minor")"
  patch="$(sanitize_int "$patch")"
fi

case "$bump_mode" in
  major)
    major="$((major + 1))"
    minor=0
    patch=0
    ;;
  minor)
    minor="$((minor + 1))"
    patch=0
    ;;
  patch)
    patch="$((patch + 1))"
    ;;
  *)
    fail "Unsupported bump mode: $bump_mode"
    ;;
esac

new_tag="v${major}.${minor}.${patch}"
while git rev-parse -q --verify "refs/tags/${new_tag}" >/dev/null; do
  patch="$((patch + 1))"
  new_tag="v${major}.${minor}.${patch}"
done

if [ -z "$commit_message" ]; then
  case "$bump_mode" in
    major)
      commit_message="feat!: snapshot large refactor (${file_count} files, +${additions} -${deletions})"
      ;;
    minor)
      commit_message="feat: snapshot large update (${file_count} files, +${additions} -${deletions})"
      ;;
    patch)
      commit_message="chore: snapshot update (${file_count} files, +${additions} -${deletions})"
      ;;
  esac
fi

git commit -m "$commit_message"

tag_message="snapshot ${new_tag}

bump: ${bump_mode}
files: ${file_count}
lines: +${additions} -${deletions}
created_at: $(date '+%Y-%m-%d %H:%M:%S %z')"

git tag -a "$new_tag" -m "$tag_message"

current_branch="$(git branch --show-current)"
echo "Created commit on ${current_branch} and tag ${new_tag}."
echo "Bump: ${bump_mode}, files: ${file_count}, lines: +${additions} -${deletions}"

if [ "$push_after" = "true" ]; then
  git push origin "$current_branch"
  git push origin "$new_tag"
  echo "Pushed ${current_branch} and ${new_tag} to origin."
fi

echo "Rollback commands:"
echo "  git checkout ${new_tag}"
echo "  git revert --no-edit ${new_tag}..HEAD  # keep history"
