# Static checks. None of these need a server.

import '_shared.just'

[doc('Run every check: syntax, ansible-lint and template rendering')]
[group('lint')]
all: syntax ansible render

[doc('Check the playbook syntax')]
[group('lint')]
syntax:
    {{ RUN }} ansible-playbook {{ PLAYBOOK }} --syntax-check

[doc('Run ansible-lint over the roles')]
[group('lint')]
ansible *args:
    {{ RUN }} ansible-lint {{ args }}

[doc('Run yamllint on its own')]
[group('lint')]
yaml *args:
    {{ RUN }} bash -lc "python -m yamllint {{ args }} ."

[doc('Render every Jinja template, which --syntax-check never does')]
[group('lint')]
render:
    {{ RUN }} ansible-playbook tests/render-templates.yml -i localhost,

[doc('Check the formatting of every justfile')]
[group('lint')]
fmt-check:
    #!/usr/bin/env bash
    set -euo pipefail
    # --fmt reads one file at a time and never follows "mod".
    fail=0
    for f in [Jj]ustfile .just/*.just; do
        just --unstable --justfile "$f" --fmt --check >/dev/null 2>&1 \
            || { echo "  needs formatting: $f"; fail=1; }
    done
    test "$fail" -eq 0 && echo "  every justfile is formatted."
    exit "$fail"

[doc('Reformat every justfile in place')]
[group('lint')]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in [Jj]ustfile .just/*.just; do
        just --unstable --justfile "$f" --fmt >/dev/null
        echo "  formatted $f"
    done

[doc('Show which runner is picked and why')]
[group('lint')]
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "  project    : {{ PROJECT }}"
    echo "  RUNNER     : ${RUNNER:-auto}"
    echo
    if command -v ansible-playbook >/dev/null 2>&1; then
        echo "  local ansible : $(ansible --version 2>/dev/null | head -1)"
        echo "                  $(command -v ansible-playbook)"
        for c in community.general ansible.posix; do
            v=$(ansible-galaxy collection list 2>/dev/null | awk -v c="$c" '$1==c {print $2; exit}')
            echo "                  ${c}: ${v:-MISSING}"
        done
    else
        echo "  local ansible : not on PATH"
    fi
    echo
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker image inspect {{ IMAGE }} >/dev/null 2>&1; then
            echo "  container     : {{ IMAGE }} present"
        else
            echo "  container     : {{ IMAGE }} not built yet"
        fi
    else
        echo "  container     : the Docker daemon is not running"
    fi
    echo
    echo "  selected:"
    RUNNER_QUIET= {{ RUN }} ansible --version >/dev/null
