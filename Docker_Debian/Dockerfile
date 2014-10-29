FROM debian:sid

RUN groupadd -r pgator && useradd -r -g pgator pgator

RUN \
apt-get update && \
apt-get -y install libevent-dev libpq5 libssl-dev && \
rm -rf /var/lib/apt/lists/*

COPY pgator /usr/bin/
COPY pgator.conf /etc/
COPY docker-entrypoint.sh /

RUN \
mkdir -p -m 2770 /var/log/pgator && \
chown pgator:pgator /var/log/pgator

EXPOSE 8080
VOLUME /var/log/pgator
ENTRYPOINT ["/docker-entrypoint.sh"]
