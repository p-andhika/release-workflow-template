## Release Process

`main` is stable. Release trains use one frozen branch identity while RC package versions and tags advance:

- Branch: `rc/vX.Y.Z-rc.1` for the train's lifetime.
- Tags: `vX.Y.Z-rc.1`, `vX.Y.Z-rc.2`, and later candidates.
- Promotion branch: `release/vX.Y.Z`.
- Stable tag: `vX.Y.Z`, created only after the promotion PR merges into `main`.

### Commands

| Command | Where | Result |
|---|---|---|
| `CONFIRM_INIT=yes npm run release:init` | `main`, first release only | Push current package version as first stable tag |
| `npm run release:patch` | `main` | Open patch `release/vX.Y.Z` PR |
| `npm run release:rc:minor` | `main` | Create `rc/vX.Y.Z-rc.1` and tag `vX.Y.Z-rc.1` |
| `npm run release:rc:major` | `main` | Create `rc/vX.Y.Z-rc.1` and tag `vX.Y.Z-rc.1` |
| `npm run release:rc` | frozen RC branch | Advance package/tag to next `-rc.N` |
| `npm run release:rc:promote` | tested frozen RC branch | Open stable promotion PR into `main` |

All commands require a clean worktree. Commands run on `main` also require local `main` to equal `origin/main`.

### Promotion

1. Start a train from `main` with `release:rc:minor` or `release:rc:major`.
2. Test the pushed RC tag. Merge fixes into the same `rc/vX.Y.Z-rc.1` branch.
3. Run `release:rc` for each new candidate. Branch stays `.1`; package version and tag advance.
4. From the tested RC branch, run `release:rc:promote`.
5. Merge the generated `release/vX.Y.Z` PR into `main`. Automation then pushes `vX.Y.Z`, publishes the GitHub release, and deletes the now-obsolete `rc/vX.Y.Z-rc.1` branch (the RC history is preserved in the `-rc.N` tags).

> **Getting your changes into a release:** branch your work off the RC branch and open the PR with **base = the RC branch** (`rc/vX.Y.Z-rc.1`), not `main`. Merge it **before** running `release:rc:promote`. A PR based on `main` will not ride the release — promote only carries what is on the RC branch, and it now **aborts** if the release would contain no real changes (only version bumps). Override a deliberate chore-only promote with `ALLOW_EMPTY_PROMOTE=yes`.

`release:patch` follows the same PR-and-post-merge-tag path without an RC train. `init` is the sole direct stable tag command and refuses to run once any `v*` tag exists.

After a tag is created, `.github/workflows/release.yml` runs two jobs:

1. `prepare-release-notes` calculates the previous release-class tag, categorizes `feat`, `fix`, `refactor`, and `perf` commits, updates `CHANGELOG.md` on `main`, and pushes the changelog commit.
2. `release` calls GitHub's `generateReleaseNotes` API with the previous tag and uses that generated body for the GitHub Release. RC tags are published as prereleases.

If tag creation succeeds but publication fails, rerun `.github/workflows/release.yml` manually with the existing tag. The publication step is idempotent and treats an existing matching GitHub Release as success.
