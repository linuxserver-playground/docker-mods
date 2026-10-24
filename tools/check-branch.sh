#!/usr/bin/env bash
# Validate a checked-out docker-mods branch before review.
#
#   tools/check-branch.sh [path-to-checkout]      (default: the current directory)
#
# Checks: mod.yml exists and validates against mod.schema.json (needs the `contracts` package from
# linuxserver-playground/builder; set PYTHON to an interpreter that has it, e.g. the builder venv), the
# branch name matches <target>-<name> when the checkout is a git branch, the Dockerfile is FROM scratch or a
# multi-stage build whose final stage is FROM scratch, every s6 run/finish/check file is executable, no
# legacy BuildImage.yml remains, and .github/workflows/build.yml calls the shared mod build.
# Exit 0 when everything passes, 1 otherwise; every finding is printed.

set -euo pipefail

dir="${1:-.}"
PYTHON="${PYTHON:-python3}"
fail=0

ok() { printf 'ok    %s\n' "$*"; }
err() { printf 'FAIL  %s\n' "$*"; fail=1; }
warn() { printf 'warn  %s\n' "$*"; }

[[ -d "${dir}" ]] || { echo "not a directory: ${dir}" >&2; exit 2; }
cd "${dir}"

# mod.yml
if [[ ! -f mod.yml ]]; then
    err "mod.yml is missing"
else
    if "${PYTHON}" -c 'import contracts' 2>/dev/null; then
        if out=$("${PYTHON}" -m contracts mod mod.yml 2>&1); then
            ok "mod.yml validates against mod.schema.json"
        else
            err "mod.yml does not validate:"
            printf '%s\n' "${out}" | sed 's/^/      /'
        fi
    else
        warn "the contracts package is not importable by ${PYTHON}; schema validation skipped (PYTHON=/path/to/builder/.venv/bin/python)"
    fi
    name=$(sed -n 's/^name:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]#]*\).*/\1/p' mod.yml | head -1)
    target=$(sed -n 's/^target:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]#]*\).*/\1/p' mod.yml | head -1)
    if [[ -n "${name}" && -n "${target}" ]]; then
        expected="${target}-${name}"
        if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) && [[ "${branch}" != "HEAD" ]]; then
            if [[ "${branch}" == "${expected}" ]]; then
                ok "branch ${branch} matches mod.yml target-name"
            elif [[ "${branch}" == "template" ]]; then
                ok "template branch (mod.yml is the example)"
            else
                err "branch is ${branch} but mod.yml says ${expected}; only the branch named ${expected} publishes"
            fi
        else
            warn "not on a git branch; cannot compare the branch name with ${expected}"
        fi
        unit_prefix="root/etc/s6-overlay/s6-rc.d/init-mod-${expected}"
        svc_prefix="root/etc/s6-overlay/s6-rc.d/svc-mod-${expected}"
        if compgen -G "${unit_prefix}*" >/dev/null || compgen -G "${svc_prefix}*" >/dev/null; then
            ok "s6 units are named after ${expected}"
        elif [[ -d root/etc/s6-overlay/s6-rc.d ]]; then
            warn "no init-mod-${expected}* or svc-mod-${expected} unit under root/etc/s6-overlay/s6-rc.d"
        fi
    fi
fi

# Dockerfile
if [[ ! -f Dockerfile ]]; then
    err "Dockerfile is missing"
else
    mapfile -t froms < <(grep -iE '^[[:space:]]*FROM[[:space:]]' Dockerfile || true)
    if (( ${#froms[@]} == 0 )); then
        err "Dockerfile has no FROM line"
    else
        last="${froms[-1]}"
        last_image=$(awk '{print tolower($2)}' <<< "${last}")
        if [[ "${last_image}" == "scratch" ]]; then
            if (( ${#froms[@]} == 1 )); then
                ok "Dockerfile is FROM scratch"
            else
                ok "Dockerfile is a ${#froms[@]}-stage build ending in FROM scratch"
            fi
        else
            err "final stage is '${last}'; a mod must end in FROM scratch (single layer)"
        fi
        for f in "${froms[@]:0:${#froms[@]}-1}"; do
            img=$(awk '{print $2}' <<< "${f}")
            case "${img}" in
                ghcr.io/linuxserver/baseimage-*|ghcr.io/linuxserver-playground/*|scratch) ;;
                *) warn "build stage uses ${img}; build stages normally use ghcr.io/linuxserver/baseimage-*" ;;
            esac
        done
    fi
    if ! grep -qiE '^[[:space:]]*COPY[[:space:]]' Dockerfile; then
        err "Dockerfile copies nothing into the layer"
    fi
    if grep -qiE '^[[:space:]]*(ENTRYPOINT|CMD|HEALTHCHECK|USER|EXPOSE)[[:space:]]' Dockerfile; then
        err "Dockerfile sets ENTRYPOINT/CMD/HEALTHCHECK/USER/EXPOSE; a mod is only files"
    fi
    if ! grep -qiE '^[[:space:]]*LABEL[[:space:]]+maintainer=' Dockerfile; then
        warn "no 'LABEL maintainer=' in the Dockerfile"
    fi
fi

# executable bits
if [[ -d root ]]; then
    bad=()
    while IFS= read -r -d '' f; do
        [[ -x "${f}" ]] || bad+=("${f}")
    done < <(find root \( -name run -o -name finish -o -name check \) -type f -print0)
    if (( ${#bad[@]} )); then
        err "not executable (chmod +x): ${bad[*]}"
    else
        ok "every run/finish/check file under root/ is executable"
    fi
    while IFS= read -r -d '' unit; do
        if [[ -f "${unit}/type" ]] && [[ "$(tr -d '[:space:]' < "${unit}/type")" == "oneshot" ]] && [[ ! -f "${unit}/up" ]]; then
            err "${unit} is a oneshot without an up file"
        fi
        if [[ -f "${unit}/run" ]] && head -c3 "${unit}/run" | grep -q $'\xef\xbb\xbf'; then
            err "${unit}/run starts with a UTF-8 BOM"
        fi
    done < <(find root/etc/s6-overlay/s6-rc.d -mindepth 1 -maxdepth 1 -type d -name '*-mod-*' -print0 2>/dev/null)
    if command -v shellcheck >/dev/null 2>&1; then
        mapfile -t scripts < <(find root \( -name run -o -name finish -o -name check \) -type f)
        if (( ${#scripts[@]} )); then
            if shellcheck -s bash "${scripts[@]}"; then
                ok "shellcheck passed"
            else
                warn "shellcheck reported findings"
            fi
        fi
    fi
else
    warn "no root/ directory"
fi

# workflows
if [[ -f .github/workflows/BuildImage.yml ]]; then
    err "legacy .github/workflows/BuildImage.yml is present; replace it with build.yml from the template branch"
fi
if [[ ! -f .github/workflows/build.yml ]]; then
    err ".github/workflows/build.yml is missing"
elif grep -q 'linuxserver-playground/workflows/.github/workflows/mod-build.yml@' .github/workflows/build.yml; then
    ok "build.yml calls the shared mod build"
else
    err "build.yml does not call linuxserver-playground/workflows mod-build.yml"
fi
for legacy in .github/workflows/permissions.yml .github/workflows/call_issue_pr_tracker.yml; do
    [[ -f "${legacy}" ]] && err "legacy workflow ${legacy} is present"
done

if (( fail )); then
    echo "check-branch: FAILED"
    exit 1
fi
echo "check-branch: all checks passed"
