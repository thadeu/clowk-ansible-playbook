# Run the playbook against the inventory.
#
# Every recipe forwards extra flags straight to Ansible:
#   just play apply --limit server01 -vvv

import '_shared.just'

[doc('Test the SSH connection to every host')]
[group('run')]
ping *args:
    {{ RUN }} ansible {{ HOSTS }} -m ping {{ args }}

[doc('Dry run: show every change, touch nothing')]
[group('run')]
check *args:
    {{ RUN }} ansible-playbook {{ PLAYBOOK }} --check --diff {{ args }}

[doc('Run the playbook')]
[group('run')]
apply *args:
    {{ RUN }} ansible-playbook {{ PLAYBOOK }} --diff {{ args }}

[doc('Run one role: just play role docker')]
[group('run')]
role name *args:
    {{ RUN }} ansible-playbook {{ PLAYBOOK }} --diff --tags {{ name }} {{ args }}

[doc('Run twice and fail if the second run changes anything')]
[group('run')]
idempotence *args:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ RUN }} ansible-playbook {{ PLAYBOOK }} {{ args }}
    echo
    echo ">> Second run. Every host must report changed=0."
    log=$(mktemp)
    trap 'rm -f "$log"' EXIT
    {{ RUN }} ansible-playbook {{ PLAYBOOK }} {{ args }} | tee "$log"
    if grep -qE 'changed=[1-9]' "$log"; then
        echo "FAIL: the second run changed something." >&2
        exit 1
    fi
    echo "OK: the playbook is idempotent."

[doc('Show the firewall, fail2ban, sshd, swap and Docker state')]
[group('inspect')]
verify *args:
    {{ RUN }} ansible {{ HOSTS }} --become {{ args }} -a "bash -c 'echo ---- UFW ----; ufw status verbose; echo ---- FAIL2BAN ----; fail2ban-client status sshd; echo ---- SSHD ----; sshd -T | grep -E \"^(port|permitrootlogin|passwordauthentication|maxauthtries) \"; echo ---- SWAP ----; swapon --show; free -h; echo ---- DOCKER ----; docker --version'"

[doc('Print the gathered facts of a host')]
[group('inspect')]
facts *args:
    {{ RUN }} ansible {{ HOSTS }} -m setup {{ args }}

[doc('Run any ansible command inside the container')]
[group('inspect')]
raw +cmd:
    {{ RUN }} {{ cmd }}

[doc('Show what is using disk: /var/log, the journal and container logs')]
[group('inspect')]
logs *args:
    {{ RUN }} ansible {{ HOSTS }} --become {{ args }} -a "bash -c 'echo ---- DISK ----; df -h / | tail -1; echo; echo ---- /var/log TOTAL ----; du -sh /var/log; echo; echo ---- 10 LARGEST IN /var/log ----; du -ah /var/log | sort -rh | head -10; echo; echo ---- JOURNAL ----; journalctl --disk-usage; echo; echo ---- CONTAINER LOGS ----; du -ch /var/lib/docker/containers/*/*-json.log 2>/dev/null | tail -1 || echo none'"
