FROM debian:8.2

# Install system dependencies
RUN apt-get update
RUN apt-get install -y wget 
RUN apt-get install -y libevent-dev libpq5 libssl-dev
RUN apt-get install -y gcc xdg-utils libcurl3-dev 
RUN apt-get install -y libcurl4-gnutls-dev
RUN apt-get install -y postgresql-client
RUN apt-get install -y git 

# Install DMD 
RUN wget http://downloads.dlang.org/releases/2.x/2.069.1/dmd_2.069.1-0_amd64.deb
RUN dpkg -i dmd_2.069.1-0_amd64.deb
RUN rm dmd_2.069.1-0_amd64.deb

# Install DUB
RUN wget http://code.dlang.org/files/dub-0.9.24-linux-x86_64.tar.gz
RUN tar -zxvf dub-0.9.24-linux-x86_64.tar.gz
RUN cp dub /usr/bin/dub 
RUN chmod a+x /usr/bin/dub
RUN rm -rf dub dub-0.9.24-linux-x86_64.tar.gz

#RUN dub --version
#RUN dmd --version

# Installing source
RUN mkdir /var/local/pgator
COPY .git /var/local/pgator/.git
COPY source /var/local/pgator/source
COPY bakeVersions.sh /var/local/pgator/bakeVersions.sh
COPY dub.json /var/local/pgator/dub.json
COPY current-pgator-backend.version /var/local/pgator/current-pgator-backend.version

# Configure
RUN groupadd -r pgator && useradd -r -g pgator pgator
RUN mkdir /var/log/pgator && chown pgator /var/log/pgator

COPY Docker_Build/pgator.conf /etc/

COPY Docker_Build/migrate-db.sql /