FROM debian:bookworm-slim

RUN bash

RUN apt-get update && \
    apt-get install -y \
        binfmt-support \
        exfatprogs \
        e2fsprogs \
        fdisk \
        file \
        git \
        kpartx \
        lsof \
        p7zip-full \
        qemu-user-static \
        unzip \
        wget \
        xz-utils \
        units \
        git \
        python3 \
        python3-pip \
        build-essential

# Install pimod from Github
WORKDIR /usr/src/pimod
RUN git clone https://github.com/aniongithub/pimod.git .

# Add pimod to PATH
ENV PATH="/usr/src/pimod:${PATH}"

# Install required python packages
RUN pip3 install pyyaml --break-system-packages