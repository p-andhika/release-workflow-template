#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/template"

bash -n "$TEMPLATE/scripts/release.sh"
for test in "$ROOT"/tests/test-*.sh; do
  bash -n "$test"
done

for file in "$TEMPLATE"/.github/workflows/*.yml; do
  ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$file"
done

bad=$(grep -RInE 'AlloFresh|build:lib|rc-v[0-9XY]|YYYYMMDD|HHMMZ|RELEASE_STABLE_BRANCH|RC_BRANCH="v\$\{' \
  "$TEMPLATE" "$ROOT/README.md" "$ROOT/CHECKLIST.md" || true)
if [[ -n "$bad" ]]; then
  echo "Forbidden project-specific or legacy content found:" >&2
  echo "$bad" >&2
  exit 1
fi

grep -Fq 'rc/vX.Y.Z-rc.1' "$TEMPLATE/README.release.md"
grep -Fq 'uses: ./.github/workflows/release.yml' "$TEMPLATE/.github/workflows/release-dispatch.yml"
grep -Fq 'Delete RC branch' "$TEMPLATE/.github/workflows/release-tag-after-merge.yml"
grep -Fq 'github.event.repository.name' "$TEMPLATE/.github/workflows/release.yml"
grep -Fq 'uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7' "$TEMPLATE/.github/workflows/release.yml"

grep -Fq 'generateReleaseNotes' "$TEMPLATE/.github/workflows/release.yml"
grep -Fq 'CHANGELOG.md' "$TEMPLATE/.github/workflows/release.yml"

for test in "$ROOT"/tests/test-*.sh; do
  bash "$test"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$TEMPLATE/scripts/release.sh" "$ROOT/scripts/verify-template.sh" "$ROOT"/tests/test-*.sh
else
  echo "skip - shellcheck unavailable"
fi

if command -v actionlint >/dev/null 2>&1; then
  actionlint "$TEMPLATE"/.github/workflows/*.yml
else
  echo "skip - actionlint unavailable"
fi

echo "Template verification passed."
