FROM debian:sid

RUN groupadd -r pgator && useradd -r -g pgator pgator

RUN \
apt-get update && \
apt-get -y install libevent-dev libpq5 libssl-dev && \
rm -rf /var/lib/apt/lists/*

COPY pgator /usr/bin/
COPY pgator.conf /etc/
COPY docker-entrypoint.sh /

EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
