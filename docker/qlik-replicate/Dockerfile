FROM amazonlinux:2023@sha256:d09f1353c3c0844852cff7bf103498a205532f5bca444e1ed6406e3c5402bb26

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN dnf install -y \
        shadow-utils \
        tar \
        gzip && \
    dnf clean all

ARG REPLICATE_FILE=areplicate-2026.5.0-169.x86_64

RUN curl -L -o ${REPLICATE_FILE}.tar.gz \
        https://github.com/qlik-download/replicate/releases/download/v2026.5.0/QlikReplicate_2026_5_0_Linux_X64.tar.gz && \
    tar -xzf ${REPLICATE_FILE}.tar.gz -C /tmp && \
    rm -f ${REPLICATE_FILE}.tar.gz && \
    systemd=no dnf -y install /tmp/${REPLICATE_FILE}.rpm && \
    dnf clean all && \
    rm -f /tmp/${REPLICATE_FILE}.rpm

RUN dnf install -y \
        util-linux \
        unixODBC \
        libnsl \
        unzip \
        inotify-tools \
        procps && \
    dnf clean all

COPY ./scripts/start_replicate.sh /opt/attunity/replicate/bin/start_replicate.sh

RUN chmod 775 /opt/attunity/replicate/bin/start_replicate.sh && \
    chown attunity:attunity /opt/attunity/replicate/bin/start_replicate.sh

ENTRYPOINT ["/opt/attunity/replicate/bin/start_replicate.sh"]
