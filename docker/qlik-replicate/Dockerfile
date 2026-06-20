FROM amazonlinux:2023@sha256:d09f1353c3c0844852cff7bf103498a205532f5bca444e1ed6406e3c5402bb26

# RUN rm -f /etc/odbcinst.ini
ENV PIP_ROOT_USER_ACTION=ignore

RUN dnf install -y \
        shadow-utils \
        tar \
        gzip && \
    dnf clean all

ARG REPLICATE_FILE=areplicate-2026.5.0-169.x86_64
RUN curl -L -o ${REPLICATE_FILE}.tar.gz \
  https://github.com/qlik-download/replicate/releases/download/v2026.5.0/QlikReplicate_2026_5_0_Linux_X64.tar.gz
RUN tar -xzf ${REPLICATE_FILE}.tar.gz -C /tmp && \
    rm -f ${REPLICATE_FILE}.tar.gz
RUN systemd=no dnf -y install /tmp/${REPLICATE_FILE}.rpm
RUN dnf clean all
RUN rm -f /tmp/${REPLICATE_FILE}.rpm

COPY ./scripts/start_replicate.sh /opt/attunity/replicate/bin/start_replicate.sh
RUN chmod 775 /opt/attunity/replicate/bin/start_replicate.sh
RUN chown attunity:attunity /opt/attunity/replicate/bin/start_replicate.sh

#install prequisits
RUN pushd /etc/yum.repos.d/
RUN dnf update -y && \
    dnf install -y \
        util-linux \
        unixODBC \
        libnsl \
        unzip \
        inotify-tools \
        procps \
        python3.12 \
        python3.12-pip \
        python3.12-setuptools \
        python3.12-wheel && \
    dnf clean all

RUN ln -s /usr/bin/pip3.12 /usr/bin/pip3

ENV PATH="/usr/bin:/usr/local/bin:${PATH}"

ARG CACHE_BUST=1
WORKDIR /opt/qlikcli
COPY qlikcli/ ./
ENV PIP_ROOT_USER_ACTION=ignore
RUN pip3 install -r ./requirements.txt && \
    pip3 install .


ENTRYPOINT ["/opt/attunity/replicate/bin/start_replicate.sh"]