#!/usr/bin/env bash
# Build a checked-out mod branch and apply it to a LinuxServer image locally.
#
#   tools/test-mod.sh [path-to-checkout] [image]
#
# `DOCKER_MODS=<image>` makes the base image fetch the mod from a registry, never from the local Docker
# daemon, so an image that only exists locally is reported as "not found in modcache". The base images do
# have a sideload path: with DOCKER_MODS_SIDELOAD=true, `DOCKER_MODS=<name>` is read from /mods/<name>.tar.
# This script builds the mod, extracts its single layer with `docker save`, mounts it there, starts the
# image, waits for `[ls.io-init] done.`, prints the log and stops the container. The mod's init lines and
# any package installation appear in the log; exit status is 0 when init finished, 1 otherwise.
#
# The default image is the mod's target (ghcr.io/linuxserver/<target>:latest), or baseimage-alpine for
# universal mods. Extra `docker run` arguments (ports, volumes, -e) go in DOCKER_RUN_ARGS.

set -euo pipefail

dir="${1:-.}"
image="${2:-}"
timeout="${TIMEOUT:-240}"

[[ -d "${dir}" ]] || { echo "not a directory: ${dir}" >&2; exit 2; }
cd "${dir}"
[[ -f mod.yml && -f Dockerfile ]] || { echo "no mod.yml and Dockerfile in ${PWD}" >&2; exit 2; }

name=$(sed -n 's/^name:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]#]*\).*/\1/p' mod.yml | head -1)
target=$(sed -n 's/^target:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]#]*\).*/\1/p' mod.yml | head -1)
[[ -n "${name}" && -n "${target}" ]] || { echo "mod.yml has no name/target" >&2; exit 2; }
if [[ -z "${image}" ]]; then
    if [[ "${target}" == "universal" ]]; then
        image="ghcr.io/linuxserver/baseimage-alpine:3.22"
    else
        image="ghcr.io/linuxserver/${target}:latest"
    fi
fi

work=$(mktemp -d)
container="modtest-${target}-${name}-$$"
# shellcheck disable=SC2329  # invoked by the trap
cleanup() {
    docker rm -f "${container}" >/dev/null 2>&1 || true
    rm -rf "${work}"
}
trap cleanup EXIT

echo "==> building ${target}-${name}"
docker build -t "mod-local:${target}-${name}" .

echo "==> extracting the layer"
mkdir -p "${work}/save" "${work}/mods"
docker save "mod-local:${target}-${name}" | tar -x -C "${work}/save"
layers=$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print(len(m[0]["Layers"])); print(m[0]["Layers"][0])' "${work}/save/manifest.json")
count=$(head -1 <<< "${layers}")
layer=$(tail -1 <<< "${layers}")
if [[ "${count}" != "1" ]]; then
    echo "FAIL  the image has ${count} layers; a mod must have exactly one" >&2
    exit 1
fi
cp "${work}/save/${layer}" "${work}/mods/${name}.tar"
chmod 644 "${work}/mods/${name}.tar"
echo "    $(tar -tf "${work}/mods/${name}.tar" | grep -vc '/$') files in the layer"

echo "==> starting ${image} with the mod sideloaded"
# shellcheck disable=SC2086
docker run -d --name "${container}" \
    -v "${work}/mods:/mods:ro" \
    -e DOCKER_MODS="${name}" -e DOCKER_MODS_SIDELOAD=true \
    -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
    ${DOCKER_RUN_ARGS:-} \
    "${image}" >/dev/null

# The log is read into a variable before grepping: with pipefail, `docker logs | grep -q` fails when grep
# closes the pipe early.
finished=0
log=""
for (( i = 0; i < timeout; i += 3 )); do
    log=$(docker logs "${container}" 2>&1 || true)
    if grep -q '\[ls.io-init\] done\.' <<< "${log}"; then
        finished=1
        break
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "${container}")" != "true" ]]; then
        log=$(docker logs "${container}" 2>&1 || true)
        break
    fi
    sleep 3
done

echo "==> container log"
printf '%s\n' "${log}"

if (( finished )); then
    if grep -q "\[mod-init\] ${name} applied to container" <<< "${log}"; then
        echo "test-mod: init finished with the mod applied"
        exit 0
    fi
    echo "test-mod: init finished but the mod was not applied" >&2
    exit 1
fi
echo "test-mod: init did not finish within ${timeout}s" >&2
exit 1
