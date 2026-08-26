# Build and manage the Ansible control-node container image.

import '_shared.just'

[doc('Build the control-node image')]
[group('image')]
build: _docker-up
    docker build -t {{ IMAGE }} .

[doc('Build again from scratch, ignoring the cache')]
[group('image')]
rebuild: _docker-up
    docker build --no-cache --pull -t {{ IMAGE }} .

[doc('Open a shell inside the control-node container')]
[group('image')]
shell *cmd: _docker-up
    RUNNER=docker {{ RUN }} {{ if cmd == '' { 'bash' } else { 'bash -lc "' + cmd + '"' } }}

[doc('Show the versions inside the image')]
[group('image')]
info: _docker-up
    #!/usr/bin/env bash
    set -euo pipefail
    RUNNER=docker {{ RUN }} bash -lc '
        ansible --version | head -2
        echo
        ansible-lint --version
        echo
        ansible-galaxy collection list 2>/dev/null | grep -E "community.general|ansible.posix"
    '
    echo
    docker image ls {{ IMAGE }} --format '  size: {{{{.Size}}'

[confirm('Remove the image? [y/N]')]
[doc('Remove the control-node image')]
[group('image')]
clean:
    -docker image rm {{ IMAGE }}
