# Manage inventory/hosts.ini.

import '_shared.just'

# hosts.ini is git-ignored, so a fresh clone does not have one. Every recipe
# that touches the inventory creates it from the example first.
[private]
_inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{ INVENTORY }}" ]; then
        cp "{{ INVENTORY }}.example" "{{ INVENTORY }}"
        echo "  created {{ INVENTORY }} from the example."
    fi

[doc('Add a VM: just inv add server02 203.0.113.11 [ubuntu]')]
[group('inventory')]
add name ip user='debian': _inventory
    #!/usr/bin/env bash
    set -euo pipefail
    if grep -qE "^{{ name }}[[:space:]]" "{{ INVENTORY }}"; then
        echo "  {{ name }} is already in {{ INVENTORY }}."
        exit 0
    fi
    line="{{ name }} ansible_host={{ ip }} ansible_user={{ user }}"
    awk -v l="$line" '/^\[servers\]/ { print; print l; next } 1' \
        "{{ INVENTORY }}" > "{{ INVENTORY }}.tmp"
    mv "{{ INVENTORY }}.tmp" "{{ INVENTORY }}"
    echo "  added to {{ INVENTORY }}:"
    echo "    $line"

[doc('Remove a VM from the inventory')]
[group('inventory')]
remove name: _inventory
    #!/usr/bin/env bash
    set -euo pipefail
    if ! grep -qE "^{{ name }}[[:space:]]" "{{ INVENTORY }}"; then
        echo "  {{ name }} is not in {{ INVENTORY }}."
        exit 0
    fi
    grep -vE "^{{ name }}[[:space:]]" "{{ INVENTORY }}" > "{{ INVENTORY }}.tmp"
    mv "{{ INVENTORY }}.tmp" "{{ INVENTORY }}"
    echo "  removed {{ name }} from {{ INVENTORY }}."

[doc('Show the raw inventory file')]
[group('inventory')]
show: _inventory
    @cat {{ INVENTORY }}

[doc('List the hosts that Ansible resolves')]
[group('inventory')]
list: _inventory
    {{ RUN }} ansible-inventory --list --yaml
