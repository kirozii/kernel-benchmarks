FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bc \
    bison \
    build-essential \
    ca-certificates \
    ccache \
    cpio \
    dwarves \
    flex \
    gcc-9 \
    g++-9 \
    kmod \
    libelf-dev \
    libssl-dev \
    make \
    rsync \
    wget \
    xz-utils \
 && rm -rf /var/lib/apt/lists/*
