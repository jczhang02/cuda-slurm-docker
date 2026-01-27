# syntax=docker/dockerfile:1
# Dockerfile for jczhang02's DL/Shanhe Training.
# A100-40GB-SXM

# base_image
FROM nvidia/cuda:12.6.3-cudnn-devel-ubuntu24.04 AS base_image
LABEL maintainer="Chengrui Zhang"

ENV DEBIAN_FRONTEND=noninteractive \
	LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib" \
	OMB_PROMPT_SHOW_PYTHON_VENV=true


RUN sed -i s@/archive.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list.d/ubuntu.sources \
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
	tmux \
	btop \
	locales \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get clean \
	&& echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
	&& locale-gen \
	&& bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"


# common
FROM base_image AS common

ARG PYTHON=python3
ARG PYTHON_VERSION=3.11.9
ARG PYTHON_SHORT_VERSION=3.11
ARG MINIFORGE3_VERSION=25.11.0-1
ARG UV_VERSION=0.9.27
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
ENV CONDA_DIR=/opt/conda

RUN wget --no-hsts --quiet https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE3_VERSION}/Miniforge3-${MINIFORGE3_VERSION}-Linux-x86_64.sh -O /tmp/miniforge.sh \
	&& /bin/bash /tmp/miniforge.sh -b -p ${CONDA_DIR} \
	&& rm /tmp/miniforge.sh \
	&& ${CONDA_DIR}/bin/conda clean --tarballs --index-cache --packages --yes \
	&& find ${CONDA_DIR} -follow -type f -name '*.a' -delete \
	&& find ${CONDA_DIR} -follow -type f -name '*.pyc' -delete \
	&& ${CONDA_DIR}/bin/conda clean --force-pkgs-dirs --all --yes \
	&& ${CONDA_DIR}/bin/conda init bash \
	&& mamba shell init --shell bash \
	&& pip install --no-cache-dir mlflow aim

COPY ./rootfs/aim ./rootfs/mlflow /etc/init.d/

COPY --from=ghcr.io/astral-sh/uv:${UV_VERSION} /uv /uvx /bin/

RUN  pip install --upgrade pip --no-cache-dir \
	&& ln -s /opt/conda/bin/pip /usr/local/bin/pip3 \
	&& apt-get update \
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

RUN mkdir -p /etc/pki/tls/certs \
	&& cp /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt

RUN rm -rf /root/.cache | true


# UNISON
FROM common AS unison
ARG UNISON_VERSION=2.53.8

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

COPY ./rootfs/slurmdbd.conf /etc/slurm/slurmdbd.conf
COPY ./rootfs/slurm.conf /etc/slurm/slurm.conf
COPY ./rootfs/cgroup.conf /etc/slurm/cgroup.conf

RUN <<EOT bash
	usermod -d /var/lib/mysql/ mysql
	mkdir /var/spool/slurmd
	mkdir /var/spool/slurmctld
	chown slurm:slurm /var/spool/slurmd
	chown slurm:slurm /var/spool/slurmctld
EOT


# Shanhe
FROM slurm AS shanhe

RUN rm -f /opt/conda/.condarc

COPY <<"EOT" /root/.condarc
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.shanhe.com/anaconda/pkgs/main
  - https://mirrors.shanhe.com/anaconda/pkgs/free
  - https://mirrors.shanhe.com/anaconda/pkgs/r
custom_channels:
  conda-forge: https://mirrors.shanhe.com/anaconda/cloud
  pytorch: https://mirrors.shanhe.com/anaconda/cloud
  msys2: https://mirrors.shanhe.com/anaconda/cloud
  bioconda: https://mirrors.shanhe.com/anaconda/cloud
ssl_verify: false
EOT

COPY <<"EOT" /root/.pip/pip.conf
[global]
index-url = https://mirrors.shanhe.com/simple
trusted-host = mirrors.shanhe.com
EOT

RUN <<EOT bash
	rm -f /etc/apt/sources.list.d/cuda.list
	sed -i "s@http://.*mirrors.aliyun.com@https://mirrors.shanhe.com@g" /etc/apt/sources.list.d/ubuntu.sources
	sed -i "s@http://.*security.ubuntu.com@https://mirrors.shanhe.com@g" /etc/apt/sources.list.d/ubuntu.sources
EOT

EXPOSE 5000 43800

# 5000: mlflow
# 43800: aim
# 6817, 6818, 6819: slurm

COPY ./rootfs/entrypoint.sh /docker/entrypoint.sh
