# ---------------------------------------------------------------------------
# Imported by every module in .just/
#
# A module has its own scope: it does not see the variables of the root
# justfile. Each module imports this file to get the same configuration and
# the same private helper recipes.
# ---------------------------------------------------------------------------

# A module recipe runs in the directory of the module file, which is .just/.
# This puts every recipe back at the project root, from any working directory.
set working-directory := '..'

PROJECT := justfile_directory()
IMAGE := env('IMAGE', 'clowk-ansible:latest')
SSH_DIR := env('SSH_DIR', home_directory() / '.ssh')
PLAYBOOK := env('PLAYBOOK', 'playbook.yml')
INVENTORY := env('INVENTORY', 'inventory/hosts.ini')
HOSTS := env('HOSTS', 'servers')

# Every Ansible command goes through this dispatcher. It picks the local
# ansible when it is usable and falls back to the container, and it prints
# which one it used. Set RUNNER=local or RUNNER=docker to force one.
#   just play apply                  auto
#   RUNNER=docker just play apply    force the container
RUN := quote(PROJECT / '.just/run.sh')

# ---------------------------------------------------------------------------
# Private helpers. [private] keeps them out of --list.
# ---------------------------------------------------------------------------

[private]
_docker-up:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v docker >/dev/null 2>&1 || {
        echo "ERROR: Docker is not installed. Install Docker Desktop." >&2
        exit 1
    }
    docker info >/dev/null 2>&1 || {
        echo "ERROR: The Docker daemon is not running." >&2
        exit 1
    }
