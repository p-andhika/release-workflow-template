#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  steps = workflow.fetch("jobs").fetch("release").fetch("steps")
  run = steps.find { |step| step["name"] == "Create GitHub release" }.fetch("run")
  File.write(ARGV.fetch(1), "#!/usr/bin/env bash\nset -euo pipefail\n#{run}")
' "$ROOT/template/.github/workflows/release.yml" "$TMP/publish.sh"
chmod +x "$TMP/publish.sh"

cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
state="${GH_STUB_STATE:?}"
if [[ "${1:-} ${2:-}" == "release view" ]]; then
  [[ -f "$state" ]]
  exit
fi
if [[ "${1:-} ${2:-}" == "release create" ]]; then
  if [[ "${GH_STUB_AMBIGUOUS:-false}" == true ]]; then
    : >"$state"
    exit 42
  fi
  : >"$state"
  exit 0
fi
exit 2
EOF
chmod +x "$TMP/bin/gh"

PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/existing" RELEASE_TAG=v1.2.3 RELEASE_NAME=fixture RELEASE_NOTES='' REPOSITORY_NAME=fixture bash -c ': >"$GH_STUB_STATE"; exec "$1"' _ "$TMP/publish.sh" >"$TMP/existing.log"
grep -Fq 'already exists' "$TMP/existing.log"
echo 'ok 1 - existing GitHub release is idempotent'

PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/ambiguous" GH_STUB_AMBIGUOUS=true RELEASE_TAG=v1.2.4-rc.1 RELEASE_NOTES='' REPOSITORY_NAME=fixture "$TMP/publish.sh" >"$TMP/ambiguous.log"
grep -Fq 'ambiguous create failure' "$TMP/ambiguous.log"
echo 'ok 2 - ambiguous release creation succeeds after remote confirmation'

echo '1..2'
