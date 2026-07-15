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
5. Merge the generated `release/vX.Y.Z` PR into `main`. Automation then pushes `vX.Y.Z` and publishes the GitHub release.

`release:patch` follows the same PR-and-post-merge-tag path without an RC train. `init` is the sole direct stable tag command and refuses to run once any `v*` tag exists.

If tag creation succeeds but GitHub Release publication fails, rerun `.github/workflows/release.yml` manually with that existing tag. Publication is idempotent: an existing matching GitHub Release is treated as success.
