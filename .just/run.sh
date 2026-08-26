#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Run an Ansible command with a local install or inside the container.
#
#   RUNNER=auto    use the local ansible when it is usable, else the container
#   RUNNER=local   force the local ansible, fail when it is not usable
#   RUNNER=docker  force the container
#
# "usable" means: ansible-playbook is on PATH and both collections that the
# roles need are installed. A local ansible without the collections would stop
# with "couldn't resolve module community.general.ufw".
# ---------------------------------------------------------------------------
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${RUNNER:-auto}"
IMAGE="${IMAGE:-clowk-ansible:latest}"
SSH_DIR="${SSH_DIR:-$HOME/.ssh}"

say() { [ -n "${RUNNER_QUIET:-}" ] || printf '%s\n' "$*" >&2; }

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

local_reason=""

# --ask-pass and --ask-become-pass make Ansible call sshpass. The image has
# it; macOS does not ship it.
wants_password() {
    local a
    for a in "$@"; do
        case "$a" in
            -k|--ask-pass|-K|--ask-become-pass) return 0 ;;
        esac
    done
    return 1
}

# $1 is the command about to run, for example ansible-playbook or
# ansible-lint. ansible-lint is often absent from a plain "pip install
# ansible", so each command is checked on its own.
local_usable() {
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        local_reason="ansible-playbook is not on PATH"
        return 1
    fi

    if ! command -v "$1" >/dev/null 2>&1; then
        local_reason="$1 is not on PATH"
        return 1
    fi

    if wants_password "$@" && ! command -v sshpass >/dev/null 2>&1; then
        local_reason="--ask-pass needs sshpass, which is not installed here"
        return 1
    fi

    local list
    if ! list="$(ansible-galaxy collection list 2>/dev/null)"; then
        local_reason="ansible-galaxy failed"
        return 1
    fi

    local missing=()
    grep -q 'community\.general' <<<"$list" || missing+=("community.general")
    grep -q 'ansible\.posix'     <<<"$list" || missing+=("ansible.posix")

    if [ ${#missing[@]} -gt 0 ]; then
        local_reason="missing collections: ${missing[*]}"
        return 1
    fi

    return 0
}

docker_usable() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

run_local() {
    local version
    version="$(ansible --version 2>/dev/null | head -1 | sed -E 's/.*\[(.*)\].*/\1/')"
    say ">> runner: local  (${version})"
    cd "$PROJECT"
    exec "$@"
}

run_docker() {
    docker_usable || die "Docker is not available and the local ansible is not usable ($local_reason)."

    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        say ">> The image $IMAGE is missing. Building it now."
        docker build -t "$IMAGE" "$PROJECT" >&2
    fi

    local tty_flag=() agent=()
    [ -t 0 ] && tty_flag=(-it)

    if [ -n "${SSH_AUTH_SOCK:-}" ]; then
        if [ "$(uname -s)" = "Darwin" ]; then
            agent=(-v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock
                   -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock)
        else
            agent=(-v "$SSH_AUTH_SOCK":/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent)
        fi
    fi

    say ">> runner: docker (${IMAGE})"
    # bash 3.2, which macOS ships, treats an empty array as unset under
    # "set -u". This expansion stays safe on every bash version.
    exec docker run --rm \
        ${tty_flag[@]+"${tty_flag[@]}"} \
        -v "$PROJECT":/ansible \
        -v "$SSH_DIR":/root/.ssh:ro \
        ${agent[@]+"${agent[@]}"} \
        -w /ansible \
        "$IMAGE" "$@"
}

case "$RUNNER" in
    local)
        local_usable "$@" || die "RUNNER=local but the local ansible is not usable: $local_reason"
        run_local "$@"
        ;;
    docker)
        run_docker "$@"
        ;;
    auto)
        if local_usable "$@"; then
            run_local "$@"
        else
            say ">> local: $local_reason. Using the container instead."
            run_docker "$@"
        fi
        ;;
    *)
        die "RUNNER must be auto, local or docker (got: $RUNNER)"
        ;;
esac
