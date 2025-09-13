FROM continuumio/miniconda3:4.12.0

LABEL maintainer="Naveen Duhan <naveen.duhan@outlook.com>"
LABEL description="MetaNextViro: Viral and Bacterial Metagenomics Pipeline"
LABEL version="2.0.0"

# Set up environment
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

# Update system packages to reduce vulnerabilities
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        git \
        procps \
        && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set environment mode (can be overridden at runtime)
ENV METANEXTVIRO_ENV_MODE=unified

# Copy environment files
COPY environments/unified.yml /tmp/unified.yml
COPY environments/ /tmp/environments/

# Install unified environment by default
RUN conda env create -f /tmp/unified.yml && \
    conda clean -afy

# Create per-process environments for flexibility
RUN for env_file in /tmp/environments/*.yml; do \
        if [ "$(basename "$env_file")" != "unified.yml" ]; then \
            conda env create -f "$env_file" || echo "Warning: Failed to create environment from $env_file"; \
        fi \
    done && \
    conda clean -afy

# Activate unified environment by default
SHELL ["/bin/bash", "-c"]
RUN echo "conda activate metanextviro-unified" >> ~/.bashrc
ENV PATH /opt/conda/envs/metanextviro-unified/bin:$PATH

# Add environment activation script
COPY docker/activate_env.sh /usr/local/bin/activate_env.sh
RUN chmod +x /usr/local/bin/activate_env.sh

# Set workdir
WORKDIR /workspace

# Copy the pipeline code
COPY . /workspace

# Add container validation script
COPY docker/validate_container.sh /usr/local/bin/validate_container.sh
RUN chmod +x /usr/local/bin/validate_container.sh

# Run container validation during build
RUN /usr/local/bin/validate_container.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/validate_container.sh --health-check

# Default command
CMD ["bash"] 