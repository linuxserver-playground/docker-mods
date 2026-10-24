# AGENTS.md - docker-mods (master branch)

## Purpose

This repository holds the Docker Mods of the `linuxserver-playground` organisation: one mod per branch, built
by the shared `mod-build.yml` workflow in `linuxserver-playground/workflows` and published as tags of
`ghcr.io/linuxserver-playground/mods`. The `master` branch holds no mod. It carries the user-facing README,
`blacklist.txt` (the banned-publisher list the base images consult), and `tools/check-branch.sh`. Consumers
are LinuxServer.io container users (`DOCKER_MODS=`), the hub (which reads every branch's `mod.yml` into the
mods index) and the website (which shows mods per image from that index). The contract is
`CONVENTIONS.md` and `schemas/mod.schema.json` in `linuxserver-playground/builder`.

Each mod branch has its own `AGENTS.md`, rendered from `mod.yml`; read that one when working on a mod.

## Layout

| Path | What |
| --- | --- |
| `README.md` | How mods work, how to write one, how to submit one. The only long-form documentation. |
| `blacklist.txt` | Registry users whose mods the base images refuse unless `RUN_BANNED_MODS` is set. One login per line. |
| `tools/check-branch.sh` | Validates a checked-out mod branch: `mod.yml` against the schema, `FROM scratch`, executable `run` files, `build.yml` present. |
| `LICENSE` | GPL-3.0, identical to every other playground repository. |
| branch `template` | Starting point for new mods: `Dockerfile`, `Dockerfile.complex`, `root/` skeleton, example `mod.yml`, `build.yml`. |
| branches `<target>-<name>` | One mod each: `Dockerfile`, `root/`, `mod.yml`, `README.md`, `AGENTS.md`, `.github/workflows/build.yml`. |

There is no `mod-list.yml` here any more; the hub generates it from the branches' manifests.

## What you may edit

On `master`: everything, by pull request. On a mod branch: `Dockerfile`, `root/` and `mod.yml` only;
`README.md`, `AGENTS.md` and `.github/workflows/build.yml` are generated from the manifest (today by hand from
`templates/agents/mod.md.j2` in the builder repo; do not hand-edit them on a branch, change the template or
the manifest). Adding a mod means a new branch named `<target>-<name>` based on `template`, never a directory on
`master`. Do not add Docker Hub, Jenkins or per-branch custom workflows; the only workflow on a mod branch is
the caller of `mod-build.yml@v1`. Nothing may reference a registry outside `ghcr.io/linuxserver-playground/`
other than the `ghcr.io/linuxserver/baseimage-*` build stages.

## How to validate

```bash
# on a checked-out mod branch, with the builder repo's venv providing the contracts package
PYTHON=/path/to/builder/.venv/bin/python tools/check-branch.sh /path/to/mod-branch-checkout
docker build -t mod:test .
docker run --rm -e DOCKER_MODS=mod:test -e PUID=1000 -e PGID=1000 ghcr.io/linuxserver/baseimage-alpine:3.22
```

`check-branch.sh` is what a reviewer runs before approving; the mod init lines (`[mod-init] Applying mod
mod:test`, the mod's own `****` lines, `[ls.io-init] done.`) in the container log are the functional test.
If you cannot run Docker, say so; never claim a test that did not happen.

## Contracts

Produces `mod.yml` on every mod branch (`mod.schema.json` in `linuxserver-playground/builder`); the hub
validates each with `python -m contracts mod` and skips invalid branches with a warning. Consumes
`mod-build.yml` from `linuxserver-playground/workflows` (inputs `name`, `target`, `multi_arch`,
`mod_version`). A change to the schema or the workflow inputs is coordinated in those repos first.

## Pull request rules

Disclose AI use in the description. One mod, one change per PR, squashed. Commit and PR titles on mod
branches are `<target>: <name> <short description>`; on `master` they are short imperative sentences. No
conventional-commit prefixes, emoji or trailers. Target the mod's own branch, never `master`, for mod
changes. Do not commit credentials.
