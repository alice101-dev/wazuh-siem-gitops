ARG WAZUH_VERSION=5.0.0-rc2
FROM wazuh/wazuh-agent:${WAZUH_VERSION}

COPY requirements.txt patch_wodle.py /tmp/

RUN dnf install -y --setopt=install_weak_deps=0 python3.12 python3.12-pip && \
    ln -s /usr/bin/python3.12 /usr/bin/python3 && \
    python3.12 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    python3.12 /tmp/patch_wodle.py && \
    dnf remove -y python3.12-pip && \
    dnf clean all && \
    rm -rf /tmp/requirements.txt /tmp/patch_wodle.py /var/cache/dnf
