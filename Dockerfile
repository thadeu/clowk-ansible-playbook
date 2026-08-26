# Ansible control node. The playbook runs from inside this image, so the
# workstation needs Docker only: no Python, no pip, no ansible-galaxy.
FROM python:3.12-slim

# Override with: docker build --build-arg ANSIBLE_CORE_VERSION=2.19 .
ARG ANSIBLE_CORE_VERSION=2.18

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-client \
        sshpass \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

# ansible-lint resolves to a release that matches the pinned core.
RUN pip install --no-cache-dir \
        "ansible-core~=${ANSIBLE_CORE_VERSION}.0" \
        ansible-lint

# The collections are baked into the image, so no network call at run time.
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install \
        -r /tmp/requirements.yml \
        -p /usr/share/ansible/collections \
    && rm /tmp/requirements.yml

# macOS OpenSSH accepts options that upstream OpenSSH does not know, and a
# ~/.ssh/config that holds one of them stops ssh with "Bad configuration
# option". IgnoreUnknown must come before the option, so this wrapper is read
# first and pulls the mounted config in after it. Host aliases keep working.
RUN printf '%s\n' \
    '# Managed by the Dockerfile. Read before the mounted ~/.ssh/config.' \
    'IgnoreUnknown UseKeychain,KeychainIntegration,SecurityKeyProvider,AppleMultiPath' \
    'Include /root/.ssh/config' \
    > /etc/ansible-ssh.conf

# ANSIBLE_SSH_ARGS overrides ssh_args from ansible.cfg. It is set here and not
# in ansible.cfg, because /etc/ansible-ssh.conf exists only in this image.
ENV ANSIBLE_SSH_ARGS="-F /etc/ansible-ssh.conf -o ControlMaster=auto -o ControlPersist=120s -o ServerAliveInterval=30"

# ANSIBLE_CONFIG is explicit because Ansible refuses to read an ansible.cfg
# that sits in a world-writable directory, which is what a bind mount looks
# like on Docker Desktop.
ENV ANSIBLE_CONFIG=/ansible/ansible.cfg \
    ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \
    ANSIBLE_HOST_KEY_CHECKING=False \
    ANSIBLE_FORCE_COLOR=1 \
    PY_COLORS=1

WORKDIR /ansible

ENTRYPOINT []
CMD ["ansible-playbook", "--version"]
