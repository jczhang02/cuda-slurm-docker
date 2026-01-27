# Deep Learning Training Environment Docker Image

<!-- PROJECT SHIELDS -->

[![MIT License][license-shield]][license-url]
[![Docker][docker-shield]][docker-url]
[![NVIDIA CUDA][cuda-shield]][cuda-url]
[![Python][python-shield]][python-url]
[![Ubuntu][ubuntu-shield]][ubuntu-url]
[![Docker][docker-shield]][docker-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">
<h3 align="center">DL/Shanhe Training Environment</h3>
<p align="center">
 A comprehensive Docker environment for deep learning training with GPU support
</p>
</div>

<!-- TABLE OF CONTENTS -->

<!-- ABOUT THE PROJECT -->

## About The Project

This Docker image provides a complete deep learning training environment optimized for A100-40GB-SXM GPUs. It includes CUDA 12.6.3, cuDNN, Python 3.11.9, and various tools for distributed training and job scheduling.

<!-- GETTING STARTED -->

## Getting Started

To get a local copy up and running, follow these simple steps.

### Prerequisites

- Docker Engine 20.10+
- NVIDIA Docker Runtime
- NVIDIA GPU with compute capability 5.2+

### Installation

1. Clone the repo

```sh
   git clone https://github.com/jczhang02/dl-training-env.git
```

2. Navigate to the project directory
   ```sh
   cd dl-training-env
   ```
3. Build the Docker image
   ```sh
   docker build -t dl-training-env:latest .
   ```

<!-- USAGE EXAMPLES -->

## Usage

### Basic Usage

Run the container with GPU support:

```sh
docker run --gpus all -it -p 6005:6005 -p 6006:6006 dl-training-env:latest
```

### Development Mode

Mount your code directory and run in development mode:

```sh
docker run --gpus all -it \
-v $(pwd)/code:/workspace \
-p 6005:6005 -p 6006:6006 -p 6007:6007 \
dl-training-env:latest
```

### Distributed Training

For multi-node training with Slurm:

```sh
docker run --gpus all -it \
--network host \
-v /shared/data:/data \
dl-training-env:latest
```

<!-- FEATURES -->

## Features

- **CUDA 12.6.3** with cuDNN for optimal GPU performance
- **Python 3.11.9** with Miniforge package manager
- **Slurm** workload manager for distributed training
- **SSH** server for remote access and multi-node communication
- **Unison** for file synchronization
- **Pre-configured mirrors** for Shanhe cloud services
- **Development tools**: vim, tmux, git, cmake, curl, wget
- **Optimized environment** for PyTorch and deep learning frameworks

## Environment Variables

Key environment variables configured in the image:

```bash
CUDA_HOME=/opt/conda
PYTHON_VERSION=3.11.9
PATH="/opt/conda/bin:${PATH}"
TORCH_CUDA_ARCH_LIST="5.2;7.0+PTX;7.5;8.0;8.6;9.0"
TZ=Asia/Shanghai
```

## Package Management

The image includes pre-configured package managers:

- **Conda/Mamba**: Configured with Shanhe mirrors
- **Pip**: Configured with Shanhe PyPI mirror
- **APT**: Configured with Shanhe Ubuntu mirrors
<!-- MARKDOWN LINKS & IMAGES -->

[license-shield]: https://img.shields.io/github/license/jczhang02/dl-training-env.svg?style=for-the-badge
[license-url]: https://github.com/jczhang02/dl-training-env/blob/master/LICENSE
[docker-shield]: https://img.shields.io/badge/docker-2496ED?style=for-the-badge&logo=docker&logoColor=white
[docker-url]: https://www.docker.com/
[cuda-shield]: https://img.shields.io/badge/CUDA-76B900?style=for-the-badge&logo=nvidia&logoColor=white
[cuda-url]: https://developer.nvidia.com/cuda-toolkit
[python-shield]: https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white
[python-url]: https://www.python.org/
[ubuntu-shield]: https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white
[ubuntu-url]: https://ubuntu.com/
