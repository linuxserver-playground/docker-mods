# Modname - Docker mod for imagename

This mod adds modname to imagename, to be installed/updated during container start.

In imagename docker arguments, set an environment variable
`DOCKER_MODS=ghcr.io/linuxserver-playground/mods:imagename-modname`

If adding multiple mods, enter them in an array separated by `|`, such as
`DOCKER_MODS=ghcr.io/linuxserver-playground/mods:imagename-modname|ghcr.io/linuxserver-playground/mods:imagename-mod2`

# Mod creation instructions

* Fork the repo, create a new branch based on the branch `template`.
* Edit the `Dockerfile` for the mod and set the `maintainer` label to your GitHub login. `Dockerfile.complex`
  is only an example and included for reference; delete it when done.
* Inspect the `root` folder contents. Edit, add and remove as necessary, and rename every
  `init-mod-imagename-modname*` and `svc-mod-imagename-modname` unit (directory names, `up` paths and the
  entries under `init-mods-end/dependencies.d`, `init-mods-package-install/dependencies.d` and
  `user/contents.d`) to your `<target>-<name>`.
* After all init scripts and services are created, run
  `find ./ -path "./.git" -prune -o \( -name "run" -o -name "finish" -o -name "check" \) -not -perm -u=x,g=x,o=x -print -exec chmod +x {} +`
  to fix permissions.
* Fill in `mod.yml`: `name` and `target` must match the branch name `<target>-<name>`, list yourself in
  `maintainers`, the base families your scripts handle in `bases`, and every environment variable the mod
  reads in `env`. The hub indexes this file and the website shows it per image. Schema:
  https://github.com/linuxserver-playground/builder/blob/main/schemas/mod.schema.json
* Do not edit `AGENTS.md` or `.github/workflows/build.yml`: `build.yml` is the same on every branch and reads
  `name`, `target` and `platforms` from `mod.yml`; the branch named `<target>-<name>` is the only one that
  publishes, to `ghcr.io/linuxserver-playground/mods:<target>-<name>`.
* Edit this readme with pertinent info, delete these instructions.
* Validate: `tools/check-branch.sh` from the `master` branch, then `docker build -t mod:test .` and
  `docker run --rm -e DOCKER_MODS=mod:test -e PUID=1000 -e PGID=1000 ghcr.io/linuxserver/baseimage-alpine:3.22`
  (or the image the mod targets) and look for the mod's lines after `[mod-init] Applying mod mod:test`.
* Ask the team to create a new branch named `<target>-<name>`. `target` should be the name of the image the
  mod will be applied to, or `universal`. The new branch will be based on the `template` branch.
* Submit a PR against the branch created by the team, commits squashed, titled
  `<target>: <name> initial release`.

## Tips and tricks

* Some images have helpers built in, these images are currently:
    * [Openvscode-server](https://github.com/linuxserver/docker-openvscode-server/pull/10/files)
    * [Code-server](https://github.com/linuxserver/docker-code-server/pull/95)
