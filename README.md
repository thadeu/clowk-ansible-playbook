# OVH Cloud VM Bootstrap Playbook

A generic Ansible playbook that prepares a new virtual machine. Run it once
after you create an instance on OVH Cloud, or run it again at any time. The
playbook is idempotent: a second run reports no change if nothing changed.

The playbook installs and configures:

| Role | Result |
| --- | --- |
| `common` | Base packages, timezone, optional hostname, automatic security updates |
| `logging` | Size ceiling for logrotate, journal size cap |
| `users` | Admin accounts, passwordless sudo, authorized SSH keys |
| `swap` | Swap file, `vm.swappiness`, `vm.vfs_cache_pressure` |
| `firewall` | UFW, default-deny incoming, SSH rate limit, allowed ports |
| `fail2ban` | fail2ban with an sshd jail that bans through UFW |
| `ssh` | sshd hardening: no root login, low `MaxAuthTries`, short grace time |
| `docker` | Docker Engine, Compose plugin, log rotation, docker group members |
| `tools` | tcpdump, tshark, netstat, sngrep, aws-cli |

Supported targets: Debian 11/12/13 and Ubuntu 20.04/22.04/24.04.
The workstation needs **Docker** and **just** only.

## Quick start

```bash
just setup                          # build the control-node image, once
just new server01 203.0.113.10      # add the VM, ping it, show the plan
just bootstrap server01             # run the playbook and show the result
```

Your `~/.ssh/*.pub` key is picked up automatically. A brand new VM with no key
installed needs `just new server01 203.0.113.10 debian --ask-pass`.

---

## 1. Requirements

**[just](https://github.com/casey/just), plus either Docker or a local
Ansible.** `just` is a single binary with no runtime dependency. Ansible itself
runs whichever way is available: see
[Local Ansible or the container](#local-ansible-or-the-container).

```bash
brew install just          # macOS
# cargo install just       # any platform with Rust
# see https://github.com/casey/just#installation for the other options

just setup
```

This builds the control-node image: `ansible-core`, `ansible-lint`,
`openssh-client`, and the two collections that the roles need
(`community.general`, `ansible.posix`). The collections are baked into the
image, so no recipe makes a network call at run time.

Run `just` at any time to list the commands.

```console
$ just
OVH VM bootstrap.  Detail of a module:  just --list play

    image ...                       # Manage the control-node container image
    inv ...                         # Manage inventory/hosts.ini
    lint ...                        # Static checks: syntax, ansible-lint, template rendering
    play ...                        # Run the playbook: ping, check, apply, verify

    [workflow]
    bootstrap name *args            # Run the playbook against one host
    new name ip user='debian' *args # Add a VM, test it, preview the changes
    setup                           # Build the control-node image
    test                            # Run every static check
```

### How the container reaches your servers

When the container runs, three things are mounted into it:

| Host path | Container path | Reason |
| --- | --- | --- |
| the project directory | `/ansible` | The playbook, the roles and the inventory |
| `~/.ssh` (read only) | `/root/.ssh` | Your private key and your SSH config |
| `$SSH_AUTH_SOCK` | the agent socket | Keeps a passphrase-protected key unlocked |

### An ~/.ssh/config is optional

You do not need one. Ansible needs a **private key** that the server accepts.
A `~/.ssh/config` only helps if you want short `Host` aliases.

Put the real address in the inventory and no config is involved:

```ini
[servers]
ovh-01 ansible_host=vps-abc123.vps.ovh.ca ansible_user=debian
```

If you do keep a config, the container reads it. macOS OpenSSH accepts a few
options that upstream OpenSSH does not know, `UseKeychain` above all, and an
unknown option stops ssh:

```
/root/.ssh/config: line 14: Bad configuration option: usekeychain
/root/.ssh/config: terminating, 2 bad configuration options
```

The image handles this. It ships `/etc/ansible-ssh.conf`, which declares
`IgnoreUnknown` for the Apple-only options and then includes your config:

```
IgnoreUnknown UseKeychain,KeychainIntegration,SecurityKeyProvider,AppleMultiPath
Include /root/.ssh/config
```

`ANSIBLE_SSH_ARGS` in the image points ssh at that file, so your `Host`
aliases keep working and your macOS config needs no change.

The agent socket is found on macOS and on Linux. Point `SSH_DIR` at another
directory if your key is not in `~/.ssh`:

```bash
SSH_DIR=/path/to/keys just play apply
```

`IMAGE`, `PLAYBOOK`, `INVENTORY` and `HOSTS` work the same way.

## 2. Configure

### 2.1 Add the VM to the inventory

```bash
just inv add server01 203.0.113.10
```

`inventory/hosts.ini` is **git-ignored**, so real hostnames never reach the
repository. The recipe creates it from
[inventory/hosts.ini.example](inventory/hosts.ini.example) on a fresh clone,
then writes the line into it.
The third argument is the default user of the OVH image: `debian` on Debian
images, `ubuntu` on Ubuntu images, `root` on some images.

```bash
just inv add server02 203.0.113.11 ubuntu
```

You can also edit the file by hand:

```ini
[servers]
server01 ansible_host=203.0.113.10 ansible_user=debian
```

### 2.2 SSH keys

Nothing to paste. The `users` role reads the public key from **the machine that
runs Ansible** and installs it on the server:

```
~/.ssh/id_ed25519.pub
~/.ssh/id_rsa.pub
~/.ssh/id_ecdsa.pub
```

Every file that exists is used, and a missing path is skipped. In the container
`~` is `/root`, and your `~/.ssh` is mounted there, so the same paths work with
both runners.

The run prints what it found before it changes anything:

```console
TASK [users : Report the keys that will be installed]
ok: [ovh-01] => "2 key(s): ['ssh-ed25519 AAAAC3NzaC1l...', 'ssh-rsa AAAAB3NzaC1y...']"
```

Override the paths, or add a key in full, in `group_vars/all.yml`:

```yaml
admin_ssh_public_key_files:
  - ~/.ssh/ovh_key.pub

admin_ssh_public_keys:
  - "ssh-ed25519 AAAAC3Nza... colleague@laptop"
```

If no key is found, the playbook stops **before it changes anything** and tells
you to run `ssh-keygen -t ed25519`.

### 2.3 The first run, when the server has no key yet

A new VM that was created **with** an SSH key already accepts your key, so
`just new` works straight away.

A VM created **without** one accepts only the password. Add `--ask-pass`:

```bash
just new ovh-01 vps-abc123.vps.ovh.ca debian --ask-pass
just bootstrap ovh-01 --ask-pass
```

`just new` detects the failure and prints that line for you:

```console
$ just new ovh-01 203.0.113.10
  The connection failed.
  A new VM with no key installed needs the password:
    just new ovh-01 203.0.113.10 debian --ask-pass
```

`--ask-pass` needs `sshpass`, which the image has and macOS does not. The
dispatcher notices and uses the container for that run, so `--ask-pass` works
even with a local Ansible.

After `just bootstrap`, the key is installed and the password is no longer
needed. Set `ssh_password_authentication: "no"` in `group_vars/all.yml` and run
again to close password login for good.

## 3. Run

The commands live in `.just/`, one file for each area. The root `justfile`
declares the modules and the workflow recipes.

```
justfile          workflow recipes + "mod" declarations
.just/
├── _shared.just  configuration and private helpers, imported by each module
├── run.sh        picks the local ansible or the container
├── image.just    just image ...   the container image
├── play.just     just play ...    running the playbook
├── lint.just     just lint ...    static checks
└── inv.just      just inv ...     inventory/hosts.ini
```

Run `just` with no argument to list everything, and `just --list MODULE` for
one module:

```console
$ just
    image ...       # Manage the control-node container image
    inv ...         # Manage inventory/hosts.ini
    lint ...        # Static checks: syntax, ansible-lint, template rendering
    play ...        # Run the playbook: ping, check, apply, verify

    [workflow]
    bootstrap name            # Run the playbook against one host
    new name ip user='debian' # Add a VM, test it, preview the changes
    setup                     # Build the control-node image
    test                      # Run every static check

$ just --list play
    [inspect]
    facts *args       # Print the gathered facts of a host
    raw +cmd          # Run any ansible command inside the container
    verify *args      # Show the firewall, fail2ban, sshd, swap and Docker state

    [run]
    apply *args       # Run the playbook
    check *args       # Dry run: show every change, touch nothing
    idempotence *args # Run twice and fail if the second run changes anything
    ping *args        # Test the SSH connection to every host
    role name *args   # Run one role: just play role docker
```

### Workflow recipes

| Command | Result |
| --- | --- |
| `just setup` | Build the control-node image |
| `just new server01 203.0.113.10` | Add the VM, ping it, then show the plan |
| `just new server02 203.0.113.11 ubuntu` | The same with another login user |
| `just bootstrap server01` | Run the playbook on one host, then verify |
| `just test` | Syntax, ansible-lint and template rendering |

`just new` shows the settings and the task list, not a dry run. On a fresh VM
a dry run cannot work: nearly every role installs a package that the next task
needs, and check mode only pretends to install it, so the run stops on the
first one. Use `just play check` on a server that this playbook already
provisioned, where the packages are in place and the output is real.

### Ansible flags go straight through

Every `play` recipe takes the remaining arguments and passes them to Ansible.
No `EXTRA='...'` wrapper:

```bash
just play apply --limit server01
just play apply --limit server01 -vvv
just play check --tags docker,firewall
just play role docker --limit server01
just play apply --skip-tags swap
just play apply -K                        # ask for the sudo password
just play raw ansible-inventory --graph   # any command inside the container
```

### Local Ansible or the container

Every Ansible command goes through [.just/run.sh](.just/run.sh). It picks the
runner and prints which one it used:

```console
$ just lint syntax
>> runner: local  (core 2.21.3)

$ just lint ansible
>> local: ansible-lint is not on PATH. Using the container instead.
>> runner: docker (clowk-ansible:latest)
```

| `RUNNER` | Behaviour |
| --- | --- |
| `auto` (default) | Use the local Ansible when it can run the command, else the container |
| `local` | Force the local Ansible. Stop with a clear message if it cannot run |
| `docker` | Force the container |

```bash
RUNNER=docker just play apply     # reproducible, pinned versions
RUNNER=local  just play apply     # fastest, no container start
just lint doctor                  # show what is installed and what is picked
```

A local Ansible counts as usable only when `ansible-playbook` **and** the
command itself are on `PATH`, **and** both `community.general` and
`ansible.posix` are installed. A local Ansible without those collections would
stop with `couldn't resolve module community.general.ufw`, so the dispatcher
falls back to the container instead.

The container builds itself the first time it is needed, so `just play ping`
works on a fresh clone with no `just setup` first.

> **Note**
> The container pins `ansible-core` (2.18 by default) and the collection
> versions. A local Ansible is whatever you installed. The two can behave
> differently: `ansible-core` 2.21 already prints a deprecation warning for
> `ansible.builtin.apt_repository` that 2.18 does not. Use `RUNNER=docker` when
> you want the run to be reproducible, and in CI.

### Inventory

```bash
just inv add server02 203.0.113.11        # writes the line under [servers]
just inv add server03 203.0.113.12 ubuntu
just inv remove server02
just inv show                             # the raw file
just inv list                             # what Ansible resolves
```

`add` and `remove` do nothing if the host is already there or already gone.

### Static checks, with no server

```bash
just test              # everything
just lint syntax       # ansible-playbook --syntax-check
just lint ansible      # ansible-lint, production profile
just lint render       # render every Jinja template and assert the output
just lint fmt          # reformat every justfile
just lint fmt-check    # fail if a justfile is not formatted
```

`just lint render` matters: `--syntax-check` never opens a Jinja template.
The play in [tests/render-templates.yml](tests/render-templates.yml) renders
each template with the role defaults, including the `ssh_port=2222` plus
`AllowUsers` path, and asserts the output.

### Shell completion

```bash
just --completions zsh  > ~/.zsh/completions/_just
just --completions bash > /etc/bash_completion.d/just
```

### First run on an image that has no Python

Some minimal images have no Python interpreter:

```bash
just play raw ansible servers -m raw -a "apt-get update && apt-get install -y python3" --become
```

### Run without Docker

Docker is the supported path. If you prefer a local Ansible:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install ansible-core ansible-lint
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbook.yml --diff
```

## 4. Configuration reference

Each role keeps its defaults in `roles/<role>/defaults/main.yml`. Override any
value in [group_vars/all.yml](group_vars/all.yml), or per host in
`host_vars/<hostname>.yml`.

### Shared

| Variable | Default | Description |
| --- | --- | --- |
| `admin_users` | `[]` | Accounts with sudo and Docker access |
| `admin_ssh_public_keys` | `[]` | Extra keys in full, added to the ones found on disk |
| `ssh_port` | `22` | Read by the `ssh`, `firewall` and `fail2ban` roles |

### common

| Variable | Default | Description |
| --- | --- | --- |
| `timezone` | `UTC` | System timezone |
| `common_hostname` | `""` | Empty keeps the hostname of the image |
| `common_extra_packages` | `[]` | Extra apt packages |
| `common_unattended_upgrades` | `true` | Automatic security updates |

### logging

Logs are the usual reason a VM runs out of disk. Every config in
`/etc/logrotate.d` on Debian is `weekly` + `rotate 4` and sets **no size
limit**, so a chatty day fills the disk long before the weekly run fires:

```console
# a 58 MB /var/log/syslog, Debian default
$ logrotate --debug /etc/logrotate.conf
considering log /var/log/syslog
  log does not need rotating
```

The role adds a global `maxsize` to `/etc/logrotate.conf`. No package config
sets `maxsize`, so the ceiling reaches all of them, including files added
later. `logrotate.timer` runs once a day, so the size is checked daily:

```console
# the same file, with the ceiling
considering log /var/log/syslog
  log needs rotating
```

The journal is capped separately, through a drop-in in
`/etc/systemd/journald.conf.d/`, which leaves the package conffile alone.

| Variable | Default | Description |
| --- | --- | --- |
| `logging_enabled` | `true` | Set to `false` to skip the role |
| `logging_logrotate_maxsize` | `50M` | Rotate at this size, without waiting for the weekly run |
| `logging_logrotate_compress` | `true` | Compress the rotated files |
| `logging_journald_max_use` | `200M` | Replaces the default of 10% of the filesystem, capped at 4G |
| `logging_journald_keep_free` | `1G` | Free space the journal always leaves |
| `logging_journald_max_file_size` | `50M` | Size of one journal file |
| `logging_journald_max_retention` | `1month` | Age limit, whatever the size |
| `logging_journald_forward_to_syslog` | `true` | `false` stores each message once instead of twice |

> **Note**
> With rsyslog and journald both running, every message is written twice: once
> to the journal and once to `/var/log/syslog`. Setting
> `logging_journald_forward_to_syslog: false` halves that, at the cost of
> `/var/log/syslog` no longer filling. The default keeps the current
> behaviour.

See what is actually using the disk:

```bash
just play logs
just play logs --limit ovh-01
```

### users

| Variable | Default | Description |
| --- | --- | --- |
| `admin_ssh_public_key_files` | `~/.ssh/id_{ed25519,rsa,ecdsa}.pub` | Read from the control node |
| `admin_sudo_group` | `sudo` | Group that gives sudo access |
| `admin_passwordless_sudo` | `true` | Write a `/etc/sudoers.d` file |
| `admin_ssh_keys_exclusive` | `false` | `true` removes every other key |

### swap

| Variable | Default | Description |
| --- | --- | --- |
| `swap_enabled` | `true` | Set to `false` to skip the role |
| `swap_size` | `2G` | Size passed to `fallocate` |
| `swap_swappiness` | `"10"` | `vm.swappiness` |

The role creates no swap file if the image already boots from a swap
partition. It prints a message instead.

### firewall

| Variable | Default | Description |
| --- | --- | --- |
| `firewall_allowed_tcp_ports` | `[80, 443]` | `ssh_port` is always open |
| `firewall_allowed_udp_ports` | `[]` | UDP ports to open |
| `firewall_rate_limit_ssh` | `true` | Deny an IP after 6 tries in 30 seconds |

### fail2ban

| Variable | Default | Description |
| --- | --- | --- |
| `fail2ban_maxretry` | `5` | Failed logins before a ban |
| `fail2ban_findtime` | `10m` | Window for the count |
| `fail2ban_bantime` | `1h` | Length of the ban |

### ssh

| Variable | Default | Description |
| --- | --- | --- |
| `ssh_permit_root_login` | `"no"` | Also accepts `prohibit-password` |
| `ssh_password_authentication` | `"yes"` | Set to `"no"` after you confirm your key |
| `ssh_allow_users` | `[]` | Empty allows every account |

### tools

| Variable | Default | Description |
| --- | --- | --- |
| `tools_enabled` | `true` | Set to `false` to skip the role |
| `tools_packages` | `tcpdump`, `tshark`, `net-tools`, `sngrep` | The diagnostic packages |
| `tools_extra_packages` | `[]` | Added to the list above |
| `tools_tshark_nonroot_capture` | `false` | Let the `wireshark` group capture without sudo |
| `tools_awscli` | `true` | Install aws-cli |
| `tools_awscli_method` | `auto` | `auto`, `apt` or `official` |
| `tools_awscli_version` | `""` | Pin a version, official installer only |

**netstat** comes from `net-tools`. `ss` from `iproute2` is the modern
equivalent and is already on the system; `net-tools` is installed because a lot
of runbooks still call `netstat`.

**tshark** asks at install time whether a non-root user may capture packets.
Ansible answers "no", so capture stays with root. `sudo tcpdump` and
`sudo tshark` work, because the admin users have passwordless sudo. To capture
without sudo:

```yaml
tools_tshark_nonroot_capture: true
```

That puts `admin_users` in the `wireshark` group and makes `/usr/bin/dumpcap`
group-executable. Log out and back in for the new group to apply.

**aws-cli** version depends on the distribution:

| Distribution | apt offers | `auto` uses |
| --- | --- | --- |
| Debian 13 trixie | awscli 2.x | apt |
| Debian 12, Ubuntu 22.04 | awscli 1.x | the official v2 installer |

`auto` reads `apt-cache policy awscli` and takes apt only when it offers
version 2. Force one with `tools_awscli_method: apt` or `official`. The
official installer puts `aws` in `/usr/local/bin` and is not managed by apt, so
set `tools_awscli_update: true` if you want it refreshed on every play.

### docker

| Variable | Default | Description |
| --- | --- | --- |
| `docker_users` | `admin_users` | Members of the `docker` group |
| `docker_clean_conflicting_sources` | `true` | Remove Docker apt sources left by an earlier install |
| `docker_keyring` | `/etc/apt/keyrings/docker.asc` | The keyring this role owns |
| `docker_sources_file` | `/etc/apt/sources.list.d/docker.sources` | The source file this role owns |
| `docker_daemon_options` | `900m` x 5 files | Rendered into `/etc/docker/daemon.json` |

Example override:

```yaml
docker_daemon_options:
  log-driver: json-file
  log-opts:
    max-size: "50m"
    max-file: "5"
  default-address-pools:
    - base: "172.30.0.0/16"
      size: 24
```

> **Note**
> The current value keeps 5 files of 900 MB, which is 4.5 GB of logs for each
> container. Lower `max-size` if the disk of the VM is small.

---

## 5. Important behaviour

### Docker bypasses UFW

Docker writes its own iptables rules. The kernel reads them before the UFW
rules. A container that publishes a port is public, even when UFW denies that
port.

Bind the container to the loopback interface when the port must stay private:

```bash
docker run -p 127.0.0.1:8080:80 nginx      # private
docker run -p 8080:80 nginx                # public, UFW does not block it
```

### Changing the SSH port

1. Set `ssh_port` in `group_vars/all.yml`.
2. Run the playbook. The `firewall` role opens the new port before the `ssh`
   role restarts sshd.
3. Add `ansible_port=<new port>` to the inventory line for the next run.

On Ubuntu 22.10 and later, sshd starts from a socket unit that holds port 22.
The `ssh` role turns that unit off when `ssh_port` is not 22, and starts the
classic service instead.

### A Docker install that was already there

`get.docker.com`, a manual install, or an older run of this role leaves a
second apt source for the same repository. apt then refuses to read **any**
source list:

```
E: Conflicting values set for option Signed-By regarding source
   https://download.docker.com/linux/debian/ trixie:
   /etc/apt/keyrings/docker.gpg != /etc/apt/keyrings/docker.asc
E: The list of sources could not be read.
```

The `docker` role removes the sources and keyrings it does not own, **before**
any apt task, because every apt task fails while the conflict is there. It then
writes one file, `/etc/apt/sources.list.d/docker.sources`, in deb822 format.

Set `docker_clean_conflicting_sources: false` to keep the other files, but the
role then fails on a host that has a conflicting source.

### Group membership needs a new session

A user that joins the `docker` group keeps the old group list in the current
shell. Log out and log in again, or run `newgrp docker`.

### Handlers run at the end

Ansible runs the handlers (`Restart SSH`, `Restart Docker`,
`Restart fail2ban`) after the last role. This is why the firewall is already
open when sshd restarts.

---

## 6. Idempotency

Run the playbook twice. The second run must report `changed=0`:

```bash
just play idempotence
just play idempotence --limit server01
```

The recipe runs the playbook two times and fails if the second run changes
anything.

The roles reach this with:

- `creates:` on the `fallocate` command, so the swap file is allocated once.
- `mkswap` only when `fallocate` reported a change, so a live swap file is
  never reformatted.
- `state: present` on every package, file, user and firewall rule.
- One owned apt source for Docker, written from a template and compared by
  content. Sources left by an earlier install are removed first.
- Templates that compare the content, not the timestamp.

`swapon --show`, `systemctl is-enabled` and the other read commands carry
`changed_when: false`, so they never report a false change.

---

## 7. Verify the result

```bash
just play verify
just play verify --limit server01
```

This prints the UFW rules, the fail2ban jail, the live sshd settings, the swap
state and the Docker version. For anything else:

```bash
just play raw ansible servers --become -a "timedatectl"
just image shell                 # or open a shell and work inside
```

## 8. Troubleshooting

| Message | Cause and fix |
| --- | --- |
| `couldn't resolve module community.general.ufw` | The image is stale. Run `just image rebuild`. |
| `Set admin_users and admin_ssh_public_keys` | Fill both lists in `group_vars/all.yml` |
| `Could not get lock /var/lib/dpkg/lock` | The image runs its first update. The `common` role retries 5 times. Wait and run again. |
| `Conflicting values set for option Signed-By` | An older Docker install. The `docker` role clears it. Update this repository and run again. |
| `Permission denied (publickey)` | The server has no key yet. Add `--ask-pass`. Or the `ansible_user` is wrong. |
| `you must install the sshpass program` | Only with `RUNNER=local`. Drop `RUNNER=local` and the container is used. |
| Connection times out after the run | The SSH port changed. Add `ansible_port=<new port>` to the inventory. |
| `Timeout waiting for privilege escalation` | The account needs a sudo password. Run `just play apply -K`. |
| `The Docker daemon is not running` | Start Docker Desktop, or run with `RUNNER=local`. |
| `Bad configuration option: usekeychain` | An old image. Run `just image rebuild`. |
| `ansible-lint is not on PATH` with `RUNNER=local` | Run `pip install ansible-lint`, or drop `RUNNER=local` to fall back to the container. |
| `Permissions 0644 for '/root/.ssh/id_rsa' are too open` | Run `chmod 600 ~/.ssh/id_rsa` on the workstation. |
| The key passphrase is asked on every host | Run `ssh-add ~/.ssh/id_rsa` on the workstation before `just play apply`. |

### Recovery after a lockout

Open the OVH Cloud console (KVM / VNC) from the customer panel, log in as
root, and remove the drop-in file:

```bash
rm /etc/ssh/sshd_config.d/99-hardening.conf
systemctl restart ssh
```

---

## 9. Layout

```
.
├── Justfile                     Workflow recipes and the module list
├── .just/                       One file for each area of the CLI
│   └── run.sh                   Picks the local ansible or the container
├── Dockerfile                   The Ansible control node
├── ansible.cfg                  Inventory path, SSH options
├── requirements.yml             Galaxy collections, baked into the image
├── .ansible-lint / .yamllint    Lint configuration
├── playbook.yml                 The single entrypoint
├── inventory/hosts.ini.example  Template. hosts.ini is git-ignored.
├── group_vars/all.yml           Your settings
├── tests/render-templates.yml   Renders every Jinja template
└── roles/
    ├── common/                  Packages, timezone, automatic updates
    ├── logging/                 logrotate ceiling, journal size cap
    ├── users/                   Accounts, sudo, SSH keys
    ├── swap/                    Swap file and sysctl
    ├── firewall/                UFW
    ├── fail2ban/                SSH jail
    ├── ssh/                     sshd hardening
    ├── docker/                  Docker Engine
    └── tools/                   tcpdump, tshark, netstat, sngrep, aws-cli
```

Role order in `playbook.yml` is intentional. `firewall` runs before `ssh` so
that a new SSH port is open before sshd restarts. `docker` runs last because
the `docker` group only exists after the package install.

Each role keeps its own defaults in `roles/<role>/defaults/main.yml`. The roles
are independent, so you can copy one into another project.
