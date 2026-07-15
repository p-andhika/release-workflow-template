# Release Workflow Template

Copyable release automation for npm projects. `template/` is the only canonical payload.

## Install Into A New Project

From the target project root, with this template repository available at `<template-repo>`:

```bash
cp -R <template-repo>/template/. .
chmod +x scripts/release.sh
```

Add package scripts:

```json
{
  "scripts": {
    "release:init": "bash scripts/release.sh init",
    "release:patch": "bash scripts/release.sh patch",
    "release:rc": "bash scripts/release.sh rc",
    "release:rc:minor": "bash scripts/release.sh rc:minor",
    "release:rc:major": "bash scripts/release.sh rc:major",
    "release:rc:promote": "bash scripts/release.sh rc:promote"
  }
}
```

## Verify Template

```bash
bash scripts/verify-template.sh
```

## Contract

- Stable line: `main`.
- Frozen train branch: `rc/vX.Y.Z-rc.1`.
- Advancing RC package versions/tags: `X.Y.Z-rc.N` / `vX.Y.Z-rc.N`.
- Promotion branch: `release/vX.Y.Z`.
- Stable tag: `vX.Y.Z`, after promotion PR merge.

Promotion always starts from the tested frozen RC branch. The RC branch itself is not merged first.

`main` is part of this template's contract, not a runtime option. Projects using another stable branch must edit:

- `STABLE_BRANCH` and `origin/main` validation in `scripts/release.sh`.
- Main branch guard in `.github/workflows/release-dispatch.yml`.
- Pull-request target in `.github/workflows/release-tag-after-merge.yml`.
- Stable-branch wording in `README.release.md`.
