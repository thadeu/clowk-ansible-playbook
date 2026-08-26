# ---------------------------------------------------------------------------
# OVH Cloud VM bootstrap. The workstation needs Docker and just only.
#
#   just                 list everything
#   just setup           build the control-node image
#   just new NAME IP     add a VM and prepare it end to end
#   just play apply      run the playbook
#
# The commands live in .just/, one file for each area.
# ---------------------------------------------------------------------------

# Manage the control-node container image
mod image '.just/image.just'

# Run the playbook: ping, check, apply, verify
mod play '.just/play.just'

# Static checks: syntax, ansible-lint, template rendering
mod lint '.just/lint.just'

# Manage inventory/hosts.ini
mod inv '.just/inv.just'

[private]
default:
    @just --list --list-heading $'\nOVH VM bootstrap.  Detail of a module:  just --list play\n\n'

[doc('Build the control-node image and show what to do next')]
[group('workflow')]
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    just image build
    echo
    echo "  The image is ready. Next:"
    echo
    echo "    1. Put your SSH public key in group_vars/all.yml"
    echo "    2. just new server01 203.0.113.10"
    echo

[doc('Add a VM, test it, preview the changes: just new server01 1.2.3.4 [user] [--ask-pass]')]
[group('workflow')]
new name ip user='debian' *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just inv add {{ name }} {{ ip }} {{ user }}
    echo
    echo ">> Testing the connection to {{ name }}."
    if ! just play ping --limit {{ name }} {{ args }}; then
        echo
        echo "  The connection failed."
        case " {{ args }} " in
            *" -k "*|*" --ask-pass "*)
                echo "  The password was refused, or the user is wrong."
                echo "  Check the login user of the image: debian, ubuntu or root."
                ;;
            *)
                echo "  A new VM with no key installed needs the password:"
                echo "    just new {{ name }} {{ ip }} {{ user }} --ask-pass"
                ;;
        esac
        exit 1
    fi
    echo
    echo ">> Dry run. Nothing is changed on the server."
    just play check --limit {{ name }} {{ args }}
    echo
    echo "  Review the output above, then run:"
    echo "    just bootstrap {{ name }} {{ args }}"

[doc('Run the playbook against one host and show the result')]
[group('workflow')]
bootstrap name *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just play apply --limit {{ name }} {{ args }}
    echo
    echo ">> The key is installed now, so verify uses key authentication."
    just play verify --limit {{ name }}

[doc('Run every static check')]
[group('workflow')]
test: lint::all
