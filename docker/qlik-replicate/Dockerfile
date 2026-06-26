FROM amazonlinux:2023@sha256:d09f1353c3c0844852cff7bf103498a205532f5bca444e1ed6406e3c5402bb26

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN dnf install -y \
        shadow-utils \
        jq \
        tar \
        gzip \
        unixODBC \
        util-linux \
        libnsl \
        unzip \
        inotify-tools \
        procps && \
    dnf clean all

ARG REPLICATE_URL="https://github.com/qlik-download/replicate/releases/download/v2026.5.0/QlikReplicate_2026_5_0_Linux_X64.tar.gz"

RUN curl -L -o /tmp/replicate.tar.gz "$REPLICATE_URL" && \
    tar -xzf /tmp/replicate.tar.gz -C /tmp && \
    rm -f /tmp/replicate.tar.gz && \
    RPM_FILE=$(ls /tmp/*.rpm) && \
    echo "Installing RPM: $RPM_FILE" && \
    systemd=no dnf -y install "$RPM_FILE" && \
    rm -f "$RPM_FILE" && \
    dnf clean all

COPY ./scripts/ /opt/attunity/replicate/bin/

RUN mkdir -p /run/secrets && \
    chmod 775 /opt/attunity/replicate/bin/*.sh && \
    chown attunity:attunity /opt/attunity/replicate/bin/*.sh

ENTRYPOINT ["/opt/attunity/replicate/bin/entrypoint.sh"]
