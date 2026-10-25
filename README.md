# Docker Mods

This repository holds the Docker Mods published by the LinuxServer.io v2 playground, one mod per branch, and
the guidance for writing your own. A Docker Mod is a tarball of files, stored as a single-layer container
image, that a LinuxServer.io container downloads and extracts over `/` on boot before any init logic runs.
This allows:

* Developers and community users to modify base containers to suit their needs without maintaining a fork of
  the main image repository
* Mods to be shared with the LinuxServer.io userbase as individual projects with their own support channels
  and development ideologies
* Zero cost hosting and build pipelines for these modifications, leveraging GitHub Actions and GitHub
  Container Registry
* Full custom configuration layers for hooking containers into each other using environment variables in a
  compose file

It is important to note to end users of this system that there are not only extreme security implications to
consuming files from sources outside of our control, but by leveraging community Mods you essentially lose
direct support from the core LinuxServer team. Our first and foremost troubleshooting step will be to remove
the `DOCKER_MODS` environment variable and replace the container with a clean LSIO one.

Again, when pulling in logic from external sources practice caution and trust the sources/community you get
them from.

## How this repository is organised

| Branch | What |
| --- | --- |
| `master` | This README, the repository `AGENTS.md`, `tools/check-branch.sh` and `blacklist.txt`. No mod lives here. |
| `template` | The starting point for a new mod: `Dockerfile`, `Dockerfile.complex`, the `root/` skeleton, an example `mod.yml` and the build workflow. |
| `<target>-<name>` | One mod. `target` is the image it applies to (`swag`, `code-server`, ...) or `universal`; `name` is the mod. |

Every mod branch carries a `mod.yml` manifest
([schema](https://github.com/linuxserver-playground/builder/blob/main/schemas/mod.schema.json)) next to its
`Dockerfile`. The manifest is the only metadata file: the
[hub](https://github.com/linuxserver-playground/hub) reads `mod.yml` from every branch to build the mods
index (`/api/v1/mods.json` and `/api/v1/catalog/<image>/mods.json`), the website gives every mod a page
(`https://linuxserver-playground.github.io/site/mods/<target>-<name>/`) and lists the mods that apply to each
image on its page and in its config lab, and `README.md`, `AGENTS.md` and `.github/workflows/build.yml` on a
mod branch are rendered from it.

> **Note**
> `mod-list.yml` is no longer hand-edited in this repository. The images a mod is meant for besides its target
> (a code-server mod that also suits openvscode-server, a universal mod suggested for calibre-web) are listed in
> its `mod.yml` under `images`. The hub generates `mod-list.yml` in the legacy shape at
> `<hub>/stores/mods/mod-list.yml` from the branches' `mod.yml` files; adding a mod means adding a branch with a
> valid manifest, nothing else.

## LinuxServer.io hosted mods

Mods built from this repository are published to GitHub Container Registry as tags of one package:
`ghcr.io/linuxserver-playground/mods:<target>-<name>` is the latest build of a mod and
`ghcr.io/linuxserver-playground/mods:<target>-<name>-<sha7>` a specific commit. Pull requests build to
`ghcr.io/linuxserver-playground/untrusted-pr/mods:<target>-<name>-pr-<n>` for reviewers only. Nothing is
published to Docker Hub.

The full list, with the images each mod applies to and the environment variables it reads, is served by the
hub at `/api/v1/mods.json` and shown on the website.

## Using a Docker Mod

Before consuming a Docker Mod ensure that its source code is publicly posted along with the build pipeline
that pushes it to a registry.

Consumption of a Docker Mod is intended to be as user friendly as possible and is achieved with the following
environment variables passed to the container:

* `DOCKER_MODS` - A single endpoint `user/endpoint:tag` or an array of endpoints separated by `|`:
  `user/endpoint:tag|user2/endpoint2:tag`
* `RUN_BANNED_MODS` - If this is set to any value you bypass our centralised filter of banned registry users
  (`blacklist.txt` on this branch) and run Mods regardless of a ban

Full example:

docker run

```bash
docker create \
  --name=nzbget \
  -e DOCKER_MODS=ghcr.io/linuxserver-playground/mods:universal-tshoot \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Europe/London \
  -p 6789:6789 \
  -v /path/to/nzbget/data:/config \
  -v /path/to/downloads:/downloads \
  --restart unless-stopped \
  ghcr.io/linuxserver-playground/nzbget
```

docker compose

```yaml
---
services:
  nzbget:
    image: ghcr.io/linuxserver-playground/nzbget:latest
    container_name: nzbget
    environment:
      - DOCKER_MODS=ghcr.io/linuxserver-playground/mods:universal-tshoot
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - /path/to/nzbget/data:/config
      - /path/to/downloads:/downloads #optional
    ports:
      - 6789:6789
    restart: unless-stopped
```

This spins up an nzbget container and applies the logic found on the
[`universal-tshoot`](https://github.com/linuxserver-playground/docker-mods/tree/universal-tshoot) branch,
which installs some basic troubleshooting tools such as dig, netstat, nslookup, etc.

## Creating and maintaining a Docker Mod

**All of the example files referenced in this section are available on the
[template](https://github.com/linuxserver-playground/docker-mods/tree/template) branch of this repo.**

We will always recommend to our users consuming Mods that they leverage ones from active community members or
projects, so transparency is key. In this repository we go over two basic methods of making a Mod; the build
itself is one shared GitHub Actions workflow
([`mod-build.yml`](https://github.com/linuxserver-playground/workflows/blob/main/.github/workflows/mod-build.yml)
in `linuxserver-playground/workflows`) that every branch calls from a short, identical
`.github/workflows/build.yml`. If you host a mod in your own repository you may use any build system you like
as long as the build is transparent.

> **Note**
> One of the core ideas to remember when creating a Mod is that it can only contain a **single image layer**.
> The examples below show how to add files directly and how to run complex logic in a build stage and copy
> the result into that single layer.

### Mod types

Only s6 v3 mods are supported. All currently supported LinuxServer base images use s6 v3; older pinned images,
forks and so on may still be using v2, and new mods will not work with those.

### Docker Mod simple - just add scripts

The `Dockerfile` on the template branch contains:

```Dockerfile
FROM scratch

# copy local files
COPY root/ /
```

For most users this will suffice: anything in the `root/` folder of the branch is added to the end user's
container at `/`.

#### Layout of a v3 mod

The most common paths to leverage for LinuxServer images are as follows. Assuming a mod name of
`universal-mymod`:

```text
.
└── root
  ├── defaults                                -- Any default config files you need to copy as part of the mod can be placed here
  └── etc
    └── s6-overlay
      └── s6-rc.d
        ├── init-mods-end
        │  └── dependencies.d
        │     └── init-mod-universal-mymod    -- If your mod does not need to install packages it should be a dependency of init-mods-end (empty file)
        ├── init-mods-package-install
        │  └── dependencies.d
        │     └── init-mod-universal-mymod    -- If your mod needs to install packages it should be a dependency of init-mods-package-install (empty file)
        ├── init-mod-universal-mymod
        │  ├── dependencies.d
        │  │  └── init-mods                   -- Tells our init logic that this depends on the `init-mods` step (empty file)
        │  ├── run                            -- This is the init logic script that runs before the services in the container. Use `chmod +x` to set proper permissions.
        │  ├── type                           -- This should contain the string `oneshot`.
        │  └── up                             -- This should contain the absolute path to `run` e.g. `/etc/s6-overlay/s6-rc.d/init-mod-universal-mymod/run`.
        ├── svc-mod-universal-mymod
        │  ├── dependencies.d
        │  │  └── init-services               -- Tells our init logic that this depends on the `init-services` step (empty file)
        │  ├── run                            -- This is the script that runs in the foreground for persistent services. Use `chmod +x` to set proper permissions.
        │  └── type                           -- This should contain the string `longrun`.
        └── user
          └── contents.d
            ├── init-mod-universal-mymod      -- Tells our init logic that we need this directory (empty file)
            └── svc-mod-universal-mymod       -- Tells our init logic that we need this directory (empty file)
```

> **Note**
> For `oneshot` scripts you can alternatively omit the `run` file entirely and use the
> [execlineb](https://skarnet.org/software/execline/execlineb.html) syntax in `up` if your requirements are
> simple enough.

#### Installing packages

v3 mods make use of a single package install process for all mods to minimise the amount of calls to external
endpoints and speed up the mod init process. If you need to install repo packages you should append them to
`/mod-repo-packages-to-install.list` for repo packages or `/mod-pip-packages-to-install.list` for pip packages
and the mod handler will install them for you. Make sure to handle both Ubuntu and Alpine package names if
your mod needs to support both, e.g.

```bash
#!/usr/bin/with-contenv bash

## Ubuntu
if [ -f /usr/bin/apt ]; then
    echo "\
        dnsutils \
        net-tools \
        iputils-ping \
        traceroute" >> /mod-repo-packages-to-install.list

fi
# Alpine
if [ -f /sbin/apk ]; then
    echo "\
        bind-tools \
        net-tools" >> /mod-repo-packages-to-install.list
fi
```

If your mod needs to take additional config steps *after* the packages have been installed, add a second
`oneshot` script and make it depend on `init-mods-package-install`, add it as a dependency of
`init-mods-end`, and add it to the content bundle, e.g.

```text
.
└── root
  └── etc
    └── s6-overlay
      └── s6-rc.d
        ├── init-mods-end
        │  └── dependencies.d
        │     └── init-mod-universal-mymod-postinstall
        ├── init-mod-universal-mymod-postinstall
        │  ├── dependencies.d
        │  │  └── init-mods-package-install
        │  ├── run
        │  ├── type
        │  └── up
        └── user
          └── contents.d
            └── init-mod-universal-mymod-postinstall
```

Services will always run last, controlled by their dependency on `init-services`.

### Docker Mod complex - sky is the limit

The `Dockerfile.complex` on the template branch contains:

```Dockerfile
## Buildstage ##
FROM ghcr.io/linuxserver/baseimage-alpine:3.22 AS buildstage

RUN \
  echo "**** install packages ****" && \
  apk add --no-cache \
    curl && \
  echo "**** grab rclone ****" && \
  mkdir -p /root-layer && \
  curl -o \
    /root-layer/rclone.deb -L \
    "https://downloads.rclone.org/v1.47.0/rclone-v1.47.0-linux-amd64.deb"

# copy local files
COPY root/ /root-layer/

## Single layer deployed image ##
FROM scratch

# Add files from buildstage
COPY --from=buildstage /root-layer/ /
```

Here we are leveraging a multi-stage Dockerfile to run custom logic and pull down an rclone deb from the
Internet to include in our image layer for distribution. Any amount of logic can be run in this build stage,
or even multiple build stages, as long as the files in the end are combined into a single folder for the
`COPY` command in the final `FROM scratch` stage.

### The manifest: `mod.yml`

Every mod branch carries a `mod.yml` validated against
[`mod.schema.json`](https://github.com/linuxserver-playground/builder/blob/main/schemas/mod.schema.json):

```yaml
schema: 1
name: mymod                  # the part of the branch name after <target>-
target: universal            # the image the mod applies to, or universal
title: My mod
summary: One or two sentences on what the mod does; the hub and the website show this.
maintainers: [your-github-login]
images: [code-server]        # optional: other images the mod is meant for, shown on their pages
bases: [alpine, ubuntu]      # base families the init scripts handle
env:                         # every variable the mod reads
  - name: MYMOD_SETTING
    description: What it does.
    default: "value"
deprecated: { status: false }
```

Optional `platforms` (default `amd64` and `arm64`), `version` (an upstream version source, same shape as in
`image.yml`, for mods that pin a tool version) and `docs` (longer Markdown shown on the mod's page) are
described in the schema.

### Building

`.github/workflows/build.yml` is the same file on every branch. It reads `name` and `target` from `mod.yml`
and calls `linuxserver-playground/workflows/.github/workflows/mod-build.yml@v1`, which builds the image with
`--no-cache --pull` for every platform in `platforms` (arm64 natively) and publishes:

| Event | Image |
| --- | --- |
| push to the branch named `<target>-<name>` | `ghcr.io/linuxserver-playground/mods:<target>-<name>` and `:<target>-<name>-<sha7>` |
| pull request | `ghcr.io/linuxserver-playground/untrusted-pr/mods:<target>-<name>-pr-<n>`, deleted when the PR closes; fork PRs build without pushing |
| push to any other branch | built, not pushed |

The branch name must be `<target>-<name>`; the shared workflow refuses to publish from any other branch.

## Submitting a mod to this repository

* Fork this repo and check out the `template` branch.
* Edit the `Dockerfile` for the mod. `Dockerfile.complex` is only an example and included for reference; delete
  it when done.
* Set the `maintainer` label to your GitHub username and list the same login in `mod.yml` `maintainers`;
  this allows us to @ you if there are breaking changes that affect or will affect your mod in the future.
* Inspect the `root` folder contents. Edit, add and remove as necessary; rename every
  `init-mod-imagename-modname*` and `svc-mod-imagename-modname` unit to your `<target>-<name>`.
* After all init scripts and services are created, run
  `find ./ -path "./.git" -prune -o \( -name "run" -o -name "finish" -o -name "check" \) -not -perm -u=x,g=x,o=x -print -exec chmod +x {} +`
  to fix permissions.
* Fill in `mod.yml`. Do not edit `README.md`, `AGENTS.md` or `.github/workflows/build.yml`; they are
  generated from the manifest:
  `docker run --rm -v "$PWD":/repo --user "$(id -u):$(id -g)" ghcr.io/linuxserver-playground/builder:latest render-mod`
  (add `--check` to only report drift).
* Run `tools/check-branch.sh` and `tools/test-mod.sh` from the `master` branch against your checkout (see
  "Testing a mod locally" below) and read the mod's lines in the container log.
* Ask the team to create a new branch named `<target>-<name>` in this repo, based on the template branch.
* Submit a PR against that branch, with the commits squashed.
* Commit and PR titles are `<target>: <name> <very brief description like "initial release" or "update">`
  (e.g. `code-server: python2 add python-pip`). Detailed description and further info go in the body.
  Disclose AI assistance in the PR description.

## Appendix

### Testing a mod locally

`DOCKER_MODS=<image>` always fetches the mod from a registry; the base images never look at the local Docker
daemon, so a freshly built `mod:test` is reported as `not found in modcache`. The base images do have a
sideload path for exactly this case: with `DOCKER_MODS_SIDELOAD=true`, each name in `DOCKER_MODS` is read
from `/mods/<name>.tar`, which is the mod's single layer.

```bash
docker build -t mod:test .
docker save mod:test | tar -x -C ./save
cp ./save/$(python3 -c 'import json; print(json.load(open("save/manifest.json"))[0]["Layers"][0])') ./mods/mymod.tar
docker run --rm -v "$PWD/mods:/mods:ro" -e DOCKER_MODS=mymod -e DOCKER_MODS_SIDELOAD=true \
  -e PUID=1000 -e PGID=1000 ghcr.io/linuxserver/baseimage-alpine:3.22
```

`tools/test-mod.sh [checkout] [image]` on the `master` branch does all of that, waits for `[ls.io-init] done.`
and prints the log; look for `[mod-init] <name> applied to container` followed by the mod's own output.

### File encoding

s6 init files must be encoded in plain `UTF-8`, and not `UTF-8 with BOM`. You can remove the BOM using your
IDE if necessary.

### Inspecting mods

To inspect the file contents of external Mods, dive is a great CLI tool:
[https://github.com/wagoodman/dive](https://github.com/wagoodman/dive)

#### With Docker

```bash
docker run --rm -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    wagoodman/dive:latest <Image Name>
```

#### Without Docker

```bash
dive <Image Name>
```

## Why `master` carries a build workflow

GitHub registers a repository's workflows from its default branch only. The `build.yml` on `master` is the same file every mod branch carries; on `master` it does nothing (there is no `mod.yml`), but its presence is what lets the mod branches be built and dispatched.
