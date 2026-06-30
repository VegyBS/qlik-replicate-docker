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

ARG DRIVER_PROFILE="mssql,snowflake"
ARG ALLOW_ONLINE_FALLBACK="true"
ARG MSSQL_VERSION="18"
ARG SNOWFLAKE_ODBC_VERSION="3.17.0"
ARG SNOWFLAKE_RPM_URL=""

COPY ./scripts/ /opt/attunity/replicate/bin/
COPY ./drivers/ /tmp/drivers/

RUN mkdir -p /run/secrets && \
    chmod +x /opt/attunity/replicate/bin/*.sh && \
    chmod +x /tmp/drivers/*/install.sh && \
    chmod +x /tmp/drivers/install_drivers.sh && \
    \
    # Promote MSSQL vars only if MSSQL is selected
    if [[ "$DRIVER_PROFILE" == *"mssql"* ]]; then \
        export MSSQL_VERSION="${MSSQL_VERSION}" \
               ALLOW_ONLINE_FALLBACK="${ALLOW_ONLINE_FALLBACK}"; \
    fi && \
    \
    # Promote Snowflake vars only if Snowflake is selected
    if [[ "$DRIVER_PROFILE" == *"snowflake"* ]]; then \
        export SNOWFLAKE_ODBC_VERSION="${SNOWFLAKE_ODBC_VERSION}" \
               SNOWFLAKE_RPM_URL="${SNOWFLAKE_RPM_URL}" \
               ALLOW_ONLINE_FALLBACK="${ALLOW_ONLINE_FALLBACK}"; \
    fi && \
    \
    # Install drivers via plugin loader
    /tmp/drivers/install_drivers.sh && \
    \
    # Cleanup
    chown attunity:attunity /opt/attunity/replicate/bin/*.sh && \
    rm -rf /tmp/drivers /var/cache/dnf

ENTRYPOINT ["/opt/attunity/replicate/bin/entrypoint.sh"]
