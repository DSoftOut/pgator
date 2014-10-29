FROM debian:sid

RUN groupadd -r pgator && useradd -r -g pgator pgator

RUN \
apt-get update && \
apt-get -y install libpq5 && \
rm -rf /var/lib/apt/lists/*

COPY pgator /usr/bin/
COPY pgator.conf /etc/

RUN \
mkdir -p -m 2770 /var/log/pgator && \
chown pgator:pgator /var/log/pgator
