# Author: Naveen Duhan
# SPDX-License-Identifier: MIT
# Description: Builds the lean MetaNextViro container image from Micromamba using the core, assembly, discovery, and Foldseek environments; heavy single-tool opt-in modules use official BioContainers.

FROM mambaorg/micromamba:1.5.10

LABEL maintainer="Naveen Duhan <naveen.duhan@sdstate.edu>"
LABEL description="MetaNextViro: Viral Metagenomics Pipeline"

USER root
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV MAMBA_ROOT_PREFIX=/opt/conda

# Copy lean container environment specs first to maximize Docker layer caching
COPY envs/core.yml envs/assembly_extra.yml envs/discovery.yml envs/foldseek.yml /tmp/envs/

# Build each isolated tier and clear package caches after every step to keep CI disk usage low
RUN micromamba create -y -n core -f /tmp/envs/core.yml && \
    micromamba clean --all --yes

RUN micromamba create -y -n assembly_extra -f /tmp/envs/assembly_extra.yml && \
    micromamba clean --all --yes

RUN micromamba create -y -n discovery -f /tmp/envs/discovery.yml && \
    micromamba clean --all --yes

RUN micromamba create -y -n foldseek -f /tmp/envs/foldseek.yml && \
    micromamba clean --all --yes && \
    rm -rf /tmp/envs

# Put wrapper shims and the core surveillance environment on PATH
ENV PATH=/usr/local/bin:/opt/conda/envs/core/bin:/usr/bin:/bin

RUN set -eu; \
    wrap_bin() { \
        env_name="$1"; shift; \
        for tool in "$@"; do \
            if [ -x "/opt/conda/envs/${env_name}/bin/${tool}" ]; then \
                printf '#!/bin/sh\nexport PATH="/opt/conda/envs/%s/bin:$PATH"\nexec "/opt/conda/envs/%s/bin/%s" "$@"\n' \
                    "${env_name}" "${env_name}" "${tool}" > "/usr/local/bin/${tool}"; \
                chmod +x "/usr/local/bin/${tool}"; \
            fi; \
        done; \
    }; \
    wrap_bin assembly_extra spades.py metaspades.py cd-hit cd-hit-est; \
    wrap_bin discovery hmmsearch hmmpress mafft FastTree fasttree iqtree iqtree2 iqtree3; \
    wrap_bin foldseek foldseek

WORKDIR /workspace
COPY . /workspace

CMD ["bash"]
