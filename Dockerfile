FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash developer \
    && mkdir -p /workspace \
    && chown -R developer:developer /workspace

USER developer

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/developer/.local/bin:${PATH}"

WORKDIR /workspace

CMD ["sleep", "infinity"]
