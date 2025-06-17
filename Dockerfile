FROM continuumio/miniconda3:4.12.0

LABEL maintainer="Naveen Duhan <naveen.duhan@outlook.com>"
LABEL description="MetaNextViro: Viral and Bacterial Metagenomics Pipeline"

# Set up environment
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

# Update system packages to reduce vulnerabilities
RUN apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy environment file
COPY environment.yml /tmp/environment.yml

# Install conda environment
RUN conda env create -f /tmp/environment.yml && \
    conda clean -afy

# Activate environment by default
SHELL ["/bin/bash", "-c"]
RUN echo "conda activate metanextviro" >> ~/.bashrc
ENV PATH /opt/conda/envs/metanextviro/bin:$PATH

# Install Nextflow
RUN conda install -c bioconda nextflow

# Set workdir
WORKDIR /workspace

# Optionally copy the pipeline code (uncomment if building with code)
COPY . /workspace

# Default command
CMD ["bash"] 