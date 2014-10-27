FROM debian:latest

RUN apt-get update
RUN apt-get -y install build-essential wget git
RUN apt-get -y install xdg-utils libcurl3 # dmd depends

# "hardcoded" way to download and install latest dmd package:
ENV DMD_VER 2.066.0
ENV DMD dmd_${DMD_VER}-0_amd64.deb

RUN wget http://downloads.dlang.org/releases/2014/${DMD}
RUN dpkg -i ${DMD}

# DUB:
RUN wget http://netcologne.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list
RUN apt-get update && apt-get -y --allow-unauthenticated install d-apt-keyring && apt-get update

#RUN apt-get -y install dmd-bin dub # Used repository with a bit outdated dmd packages, dmd-bin is disabled
RUN apt-get -y install dub
