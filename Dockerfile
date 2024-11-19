# syntax=docker/dockerfile:1
# Dockerfile for jczhang02's DL/Shanhe Training.
# A100-40GB-SXM

# base_image
FROM nvidia/cuda:11.7.1-cudnn8-devel-ubuntu20.04 AS base_image
LABEL maintainer="Chengrui Zhang"

ENV DEBIAN_FRONTEND=noninteractive \
	LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"

RUN sed -i s@/archive.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list \
	&& chmod 1777 /tmp \
	&& apt-get update \
	&& apt-get install -y \
	build-essential \
	bash-completion \
	ca-certificates \
	net-tools \
	cmake \
	curl \
	git \
	direnv \
	jq \
	libssl-dev \
	libtool \
	openssl \
	python3-dev \
	unzip \
	vim \
	wget \
	tzdata \
	locales \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get clean \
	&& echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
	&& locale-gen


# common
FROM base_image AS common

ARG PYTHON=python3
ARG PYTHON_VERSION=3.11.9
ARG PYTHON_SHORT_VERSION=3.11
ARG MINIFORGE3_VERSION=24.3.0-0
ARG DEBIAN_FRONTEND=noninteractive

ENV CUDA_HOME=/opt/conda
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/conda/lib:${LD_LIBRARY_PATH}"
ENV PYTHONIOENCODING=UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PATH="/opt/conda/bin:${PATH}"
ENV TORCH_CUDA_ARCH_LIST="5.2;7.0+PTX;7.5;8.0;8.6;9.0"
ENV TORCH_NVCC_FLAGS="-Xfatbin -compress-all"
ENV CMAKE_PREFIX_PATH="$(dirname $(which conda))/../"
ENV TZ=Asia/Shanghai
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

RUN curl -L -o ~/miniforge3.sh https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE3_VERSION}/Miniforge3-${MINIFORGE3_VERSION}-Linux-x86_64.sh \
	&& chmod +x ~/miniforge3.sh \
	&& ~/miniforge3.sh -b -p /opt/conda \
	&& rm ~/miniforge3.sh \
	&& /opt/conda/bin/conda init bash \
	&& /opt/conda/bin/mamba init bash

RUN  pip install --upgrade pip --no-cache-dir \
	&& ln -s /opt/conda/bin/pip /usr/local/bin/pip3

RUN apt-get update \
	&& apt-get install -y  --allow-downgrades --allow-change-held-packages --no-install-recommends \
	&& apt-get install -y --no-install-recommends openssh-client openssh-server \
	&& mkdir -p /var/run/sshd \
	&& cat /etc/ssh/ssh_config | grep -v StrictHostKeyChecking > /etc/ssh/ssh_config.new \
	&& echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config.new \
	&& mv /etc/ssh/ssh_config.new /etc/ssh/ssh_config \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get clean

RUN mkdir -p /var/run/sshd && \
	sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

RUN rm -rf /root/.ssh/ && \
	mkdir -p /root/.ssh/ && \
	ssh-keygen -q -t rsa -N '' -f /root/.ssh/id_rsa && \
	cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys \
	&& printf "Host *\n StrictHostKeyChecking no\n" >> /root/.ssh/config

RUN mkdir -p /etc/pki/tls/certs && cp /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt

RUN rm -rf /root/.cache | true


# UNISON
FROM common AS unison
ARG UNISON_VERSION=2.53.3

RUN mkdir -p /tmp/unison \
	&& curl -L https://github.com/bcpierce00/unison/releases/download/v2.53.3/unison-2.53.3+ocaml4.08-ubuntu-x86_64.tar.gz | tar zxv -C /tmp/unison \
	&& cp /tmp/unison/bin/* /usr/local/bin/ \
	&& rm -rf /tmp/unison \
	&& echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

RUN rm -rf /root/.cache | true

# Slurm
FROM unison AS slurm

RUN <<EOT bash
	apt-get update
	apt-get install -y munge mysql-server slurm-wlm slurmdbd
	apt-get clean
	rm -rf /var/lib/apt/lists/* 
EOT

COPY <<"EOT" /etc/mysql/conf.d/mysql.cnf
[mysqld]
	innodb_buffer_pool_size=1024M
	innodb_log_file_size=64M
	innodb_lock_wait_timeout=900
EOT

COPY ./appendix/slurmdbd.conf /etc/slurm-llnl/slurmdbd.conf
COPY ./appendix/slurm.conf /etc/slurm-llnl/slurm.conf

# TODO: change file in server
COPY <<"EOT" /etc/slurm-llnl/gres.conf
NodeName=localhost Name=gpu File=/dev/nvidia[6-7]
EOT

RUN <<EOT bash
	mkdir /var/spool/slurmd
	mkdir /var/spool/slurmctld
	chmod -R 777 /var/spool/slurmd
	chmod -R 777 /var/spool/slurmctld
EOT


# Shanhe
FROM slurm AS shanhe

# RUN echo "10.251.102.1 mirrors.shanhe.com" >> /etc/hosts

COPY <<"EOT" /root/.condarc
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.shanhe.com/anaconda/pkgs/main
  - https://mirrors.shanhe.com/anaconda/pkgs/r
  - https://mirrors.shanhe.com/anaconda/pkgs/msys2
custom_channels:
  bioconda: https://mirrors.shanhe.com/anaconda/cloud
  conda-forge: https://mirrors.shanhe.com/anaconda/cloud
ssl_verify: false
EOT

COPY <<"EOT" /root/.pip/pip.conf
[global]
index-url = https://mirrors.shanhe.com/simple
trusted-host = mirrors.shanhe.com
EOT

COPY <<"EOT" /etc/apt/sources.list
deb https://mirrors.shanhe.com/ubuntu/ focal main restricted universe multiverse
deb-src https://mirrors.shanhe.com/ubuntu/ focal main restricted universe multiverse
deb https://mirrors.shanhe.com/ubuntu/ focal-security main restricted universe multiverse
deb-src https://mirrors.shanhe.com/ubuntu/ focal-security main restricted universe multiverse
deb https://mirrors.shanhe.com/ubuntu/ focal-updates main restricted universe multiverse
deb-src https://mirrors.shanhe.com/ubuntu/ focal-updates main restricted universe multiverse
deb https://mirrors.shanhe.com/ubuntu/ focal-backports main restricted universe multiverse
deb-src https://mirrors.shanhe.com/ubuntu/ focal-backports main restricted universe multiverse
EOT

COPY ./appendix/entrypoint.sh /docker/entrypoint.sh
ENTRYPOINT ["sh", "/docker/entrypoint.sh"]
