FROM continuumio/miniconda3:4.12.0

LABEL maintainer="Naveen Duhan <naveen.duhan@outlook.com>"
LABEL description="MetaNextViro: Viral and Bacterial Metagenomics Pipeline"

# Set up environment
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

# Update system packages and clean up
RUN apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy environment file and install conda environment
# This is done in a single layer to optimize build caching
COPY environment.yml /tmp/environment.yml
RUN conda env create -f /tmp/environment.yml && \
    conda clean -afy

# Activate the environment for subsequent commands
# and set the PATH. This makes the environment's binaries available.
SHELL ["/bin/bash", "-c"]
RUN echo "conda activate metanextviro" >> ~/.bashrc
ENV PATH /opt/conda/envs/metanextviro/bin:$PATH

# Set workdir
WORKDIR /workspace

# Copy the pipeline code last to leverage Docker layer caching.
# The environment will only be rebuilt if environment.yml changes.
COPY . /workspace

# Default command
CMD ["bash"]