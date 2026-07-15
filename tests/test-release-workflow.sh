#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0

ok() {
  pass=$((pass + 1))
  printf 'ok %d - %s\n' "$pass" "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"
}

assert_contains() {
  if ! grep -Fq "$2" "$1"; then
    printf '%s\n' "--- $1 ---" >&2
    sed -n '1,120p' "$1" >&2
    fail "$3: '$2' not found"
  fi
}

assert_not_contains() {
  ! grep -Fq "$2" "$1" || fail "$3: unexpected '$2'"
}

setup_repo() {
  local name="$1"
  local version="${2:-1.0.0}"
  local bare="$TMP/${name}.git"
  local repo="$TMP/$name"

  git init --bare -q "$bare"
  git init -q -b main "$repo"
  (
    cd "$repo"
    git config user.name Test
    git config user.email test@example.com
    printf '{"name":"fixture","version":"%s","private":true}\n' "$version" >package.json
    npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null
    mkdir -p scripts
    cp "$ROOT/template/scripts/release.sh" scripts/release.sh
    chmod +x scripts/release.sh
    git add package.json package-lock.json scripts/release.sh
    git commit -qm init
    git remote add origin "$bare"
    git push -q -u origin main
  )
  printf '%s\n' "$repo"
}

make_gh_stub() {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
state="${GH_STUB_STATE:?}"
if [[ "${1:-} ${2:-}" == "pr list" ]]; then
  [[ -f "$state" ]] && printf 'https://github.example/pr/1\n'
  exit 0
fi
if [[ "${1:-} ${2:-}" == "pr create" ]]; then
  if [[ "${GH_STUB_FAIL:-false}" == true ]]; then
    exit 42
  fi
  if [[ "${GH_STUB_AMBIGUOUS:-false}" == true ]]; then
    : >"$state"
    exit 42
  fi
  : >"$state"
  printf 'https://github.example/pr/1\n'
  exit 0
fi
exit 2
EOF
  chmod +x "$TMP/bin/gh"
}

run_expect_fail() {
  local output="$1"
  shift
  if "$@" >"$output" 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

make_gh_stub
REPO="$(setup_repo train)"

MAJOR_REPO="$(setup_repo major 1.2.3)"
(
  cd "$MAJOR_REPO"
  GITHUB_OUTPUT="$TMP/major.out" bash scripts/release.sh rc:major >"$TMP/major.log"
)
assert_eq "$(git -C "$MAJOR_REPO" branch --show-current)" "rc/v2.0.0-rc.1" "rc:major branch"
git --git-dir="$TMP/major.git" show-ref --verify --quiet refs/tags/v2.0.0-rc.1 || fail "major RC tag missing"
ok "rc:major creates next-major RC train"

PATCH_REPO="$(setup_repo patch 1.2.3)"
cat >"$TMP/patch.git/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
while read -r _ _ ref; do
  [[ "$ref" == refs/heads/release/* ]] && exit 1
done
EOF
chmod +x "$TMP/patch.git/hooks/pre-receive"
(
  cd "$PATCH_REPO"
  run_expect_fail "$TMP/patch-push-fail.log" env PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-patch" bash scripts/release.sh patch
)
assert_eq "$(git -C "$PATCH_REPO" branch --show-current)" "main" "patch push failure source branch"
git -C "$PATCH_REPO" show-ref --verify --quiet refs/heads/release/v1.2.4 || fail "patch push failure did not preserve local recovery branch"
! git --git-dir="$TMP/patch.git" show-ref --verify --quiet refs/heads/release/v1.2.4 || fail "rejected patch branch reached remote"
rm "$TMP/patch.git/hooks/pre-receive"
(
  cd "$PATCH_REPO"
  PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-patch" bash scripts/release.sh patch >"$TMP/patch.log"
)
git --git-dir="$TMP/patch.git" show-ref --verify --quiet refs/heads/release/v1.2.4 || fail "patch release branch missing"
assert_contains "$TMP/patch.log" "PR created: https://github.example/pr/1" "patch PR creation"
ok "patch recovers from release-branch push failure"

BAD_EXTRA_REPO="$(setup_repo bad-extra 1.2.3)"
(
  cd "$BAD_EXTRA_REPO"
  git switch -q -c release/v1.2.4
  npm version 1.2.4 --no-git-tag-version --ignore-scripts >/dev/null
  printf unrelated >unexpected.txt
  git add package.json package-lock.json unexpected.txt
  git commit -qm forged
  git switch -q main
  run_expect_fail "$TMP/bad-extra.log" env PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-bad-extra" bash scripts/release.sh patch
)
assert_contains "$TMP/bad-extra.log" "contains changes outside expected package metadata" "unrelated recovery rejection"
! git --git-dir="$TMP/bad-extra.git" show-ref --verify --quiet refs/heads/release/v1.2.4 || fail "unrelated recovery branch reached remote"
ok "local recovery rejects unrelated changes"

BAD_LOCK_REPO="$(setup_repo bad-lock 1.2.3)"
(
  cd "$BAD_LOCK_REPO"
  git switch -q -c release/v1.2.4
  npm version 1.2.4 --no-git-tag-version --ignore-scripts >/dev/null
  git checkout main -- package-lock.json
  node -e 'const fs=require("fs"); const p=require("./package-lock.json"); p.forged=true; fs.writeFileSync("package-lock.json", JSON.stringify(p, null, 2)+"\n")'
  git add package.json package-lock.json
  git commit -qm forged
  git switch -q main
  run_expect_fail "$TMP/bad-lock.log" env PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-bad-lock" bash scripts/release.sh patch
)
assert_contains "$TMP/bad-lock.log" "wrong lockfile version" "stale lockfile recovery rejection"
! git --git-dir="$TMP/bad-lock.git" show-ref --verify --quiet refs/heads/release/v1.2.4 || fail "stale-lock recovery branch reached remote"
ok "local recovery rejects stale lockfile metadata"

FAIL_REPO="$(setup_repo metadata-fail)"
mkdir -p "$TMP/fail-bin"
cat >"$TMP/fail-bin/npm" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod +x "$TMP/fail-bin/npm"
(
  cd "$FAIL_REPO"
  run_expect_fail "$TMP/metadata-fail.log" env PATH="$TMP/fail-bin:$PATH" bash scripts/release.sh rc:minor
)
assert_eq "$(git -C "$FAIL_REPO" branch --show-current)" "main" "metadata failure branch cleanup"
[[ -z "$(git -C "$FAIL_REPO" status --porcelain)" ]] || fail "metadata failure left dirty worktree"
! git -C "$FAIL_REPO" show-ref --verify --quiet refs/heads/rc/v1.1.0-rc.1 || fail "metadata failure left local RC branch"
ok "metadata update failure rolls back local RC state"

(
  cd "$REPO"
  GITHUB_OUTPUT="$TMP/rc1.out" bash scripts/release.sh rc:minor >"$TMP/rc1.log"
)
assert_eq "$(git -C "$REPO" branch --show-current)" "rc/v1.1.0-rc.1" "rc:minor branch"
assert_eq "$(node -p "require('$REPO/package.json').version")" "1.1.0-rc.1" "rc:minor package version"
assert_eq "$(node -p "require('$REPO/package-lock.json').version")" "1.1.0-rc.1" "rc:minor lockfile version"
assert_eq "$(node -p "require('$REPO/package-lock.json').packages[''].version")" "1.1.0-rc.1" "rc:minor lockfile root version"
(cd "$REPO" && npm ci --ignore-scripts --no-audit --no-fund >/dev/null)
git --git-dir="$TMP/train.git" show-ref --verify --quiet refs/heads/rc/v1.1.0-rc.1 || fail "remote RC branch missing"
git --git-dir="$TMP/train.git" show-ref --verify --quiet refs/tags/v1.1.0-rc.1 || fail "remote RC tag missing"
assert_contains "$TMP/rc1.out" "tag=v1.1.0-rc.1" "rc:minor workflow output"
ok "compact package JSON creates namespaced RC branch and updates lockfile"

(
  cd "$REPO"
  GITHUB_OUTPUT="$TMP/rc2.out" bash scripts/release.sh rc >"$TMP/rc2.log"
)
assert_eq "$(git -C "$REPO" branch --show-current)" "rc/v1.1.0-rc.1" "frozen RC branch"
assert_eq "$(node -p "require('$REPO/package.json').version")" "1.1.0-rc.2" "incremented package version"
assert_eq "$(node -p "require('$REPO/package-lock.json').version")" "1.1.0-rc.2" "incremented lockfile version"
git --git-dir="$TMP/train.git" show-ref --verify --quiet refs/tags/v1.1.0-rc.2 || fail "remote rc.2 tag missing"
assert_contains "$TMP/rc2.out" "tag=v1.1.0-rc.2" "rc workflow output"
ok "RC tags advance while branch identity stays rc.1"

(
  cd "$REPO"
  git reset --hard HEAD~1 >/dev/null
  run_expect_fail "$TMP/stale-rc.log" bash scripts/release.sh rc
  git reset --hard origin/rc/v1.1.0-rc.1 >/dev/null
)
assert_contains "$TMP/stale-rc.log" "must be aligned with 'origin/rc/v1.1.0-rc.1'" "stale RC rejection"
ok "stale local RC branch is rejected"

(
  cd "$REPO"
  git branch -m rc/v9.9.9-rc.1
  run_expect_fail "$TMP/mismatch.log" bash scripts/release.sh rc
  git branch -m rc/v1.1.0-rc.1
)
assert_contains "$TMP/mismatch.log" "does not match package base" "base mismatch rejection"
ok "branch/package base mismatch is rejected"

(
  cd "$REPO"
  printf dirty >dirty.txt
  run_expect_fail "$TMP/dirty.log" bash scripts/release.sh rc
  rm dirty.txt
)
assert_contains "$TMP/dirty.log" "working tree and index must be clean" "dirty worktree rejection"
ok "dirty worktree is rejected before mutation"

(
  cd "$REPO"
  run_expect_fail "$TMP/promote-fail.log" env PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-hard-fail" GH_STUB_FAIL=true bash scripts/release.sh rc:promote
)
assert_contains "$TMP/promote-fail.log" "gh failed to create PR" "promotion failure"
assert_not_contains "$TMP/promote-fail.log" "PR created:" "false promotion success"
assert_eq "$(git -C "$REPO" branch --show-current)" "rc/v1.1.0-rc.1" "source branch restored after PR failure"
ok "promotion fails closed when gh fails"

(
  cd "$REPO"
  PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-ambiguous" GH_STUB_AMBIGUOUS=true bash scripts/release.sh rc:promote >"$TMP/promote-ambiguous.log"
)
assert_contains "$TMP/promote-ambiguous.log" "PR created: https://github.example/pr/1" "ambiguous PR recovery"
ok "ambiguous gh failure succeeds when matching PR exists"

(
  cd "$REPO"
  PATH="$TMP/bin:$PATH" GH_STUB_STATE="$TMP/pr-ambiguous" bash scripts/release.sh rc:promote >"$TMP/promote-ok.log"
)
assert_contains "$TMP/promote-ok.log" "PR created: https://github.example/pr/1" "successful promotion"
git --git-dir="$TMP/train.git" show-ref --verify --quiet refs/heads/release/v1.1.0 || fail "remote release branch missing"
assert_eq "$(git --git-dir="$TMP/train.git" show refs/heads/release/v1.1.0:package.json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).version))')" "1.1.0" "promoted package version"
ok "successful promotion pushes stable release branch and creates PR"

INIT_REPO="$(setup_repo first 2.0.0)"
(
  cd "$INIT_REPO"
  GITHUB_OUTPUT="$TMP/init.out" CONFIRM_INIT=yes bash scripts/release.sh init >"$TMP/init.log"
)
git --git-dir="$TMP/first.git" show-ref --verify --quiet refs/tags/v2.0.0 || fail "initial remote tag missing"
assert_contains "$TMP/init.out" "tag=v2.0.0" "init workflow output"
(
  cd "$INIT_REPO"
  run_expect_fail "$TMP/init-again.log" env CONFIRM_INIT=yes bash scripts/release.sh init
)
assert_contains "$TMP/init-again.log" "v* tag exists" "repeat init rejection"
ok "init pushes first stable tag once and then refuses repeats"

LOCAL_INIT_REPO="$(setup_repo local-first 3.0.0)"
(
  cd "$LOCAL_INIT_REPO"
  CONFIRM_INIT=yes bash scripts/release.sh init >"$TMP/local-init.log"
)
git --git-dir="$TMP/local-first.git" show-ref --verify --quiet refs/tags/v3.0.0 || fail "local init remote tag missing"
assert_contains "$TMP/local-init.log" "Pushed initial tag v3.0.0" "local init success"
ok "local CLI release succeeds without GITHUB_OUTPUT"

printf '1..%d\n' "$pass"
