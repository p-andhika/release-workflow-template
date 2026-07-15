# Release Workflow Checklist

Use this when adding the template to a new project.

## Copy

- Copy `template/.` into the project root.
- Merge `README.release.md` into project documentation if desired.
- Add package scripts for `release:init`, `release:patch`, `release:rc`, `release:rc:minor`, `release:rc:major`, and `release:rc:promote`.
- Run `chmod +x scripts/release.sh`.

## Validate

In this template repository:

```bash
bash scripts/verify-template.sh
```

In the target project after copying `template/.`:

```bash
bash -n scripts/release.sh
git diff --check
```

Review the copied workflow diff before committing. The full disposable Git/NPM lifecycle suite stays in this template repository rather than being copied into every project.

Expected:

- Disposable local git/origin behavior tests pass without network or GitHub writes.
- RC train branch stays `rc/vX.Y.Z-rc.1` while RC tags advance.
- Package lock version follows package version.
- Promotion fails closed when `gh` fails.

## Required GitHub Settings

- Allow Actions to create pull requests.
- Protect `main` and allow GitHub Actions to push release branches and tags.
- Keep workflow permissions at their file-defined minimum.

## Migration Caveat

Existing release trains using another branch convention cannot continue through this template. Finish them before migration or start a new `rc/vX.Y.Z-rc.1` train from `main`.
