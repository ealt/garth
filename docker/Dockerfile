FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  git \
  jq \
  openssl \
  python3 \
  python3-pip \
  gnupg \
  && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash agent

# Git credential helper reads GitHub token from mounted file.
RUN cat > /usr/local/bin/garth-git-credential-helper << 'SCRIPT' \
 && chmod +x /usr/local/bin/garth-git-credential-helper
#!/usr/bin/env bash
set -euo pipefail
token_file="${GARTH_GITHUB_TOKEN_FILE:-/run/garth/github_token}"
token=""
if [[ -f "$token_file" ]]; then
  token="$(cat "$token_file")"
fi
echo "protocol=https"
echo "host=github.com"
echo "username=x-access-token"
echo "password=$token"
SCRIPT

RUN git config --system credential.helper /usr/local/bin/garth-git-credential-helper

USER agent
WORKDIR /work

FROM base AS claude
USER root
RUN npm install -g @anthropic-ai/claude-code
USER agent

FROM base AS codex
USER root
RUN npm install -g @openai/codex
USER agent

FROM base AS opencode
USER root
RUN npm install -g opencode-ai
USER agent

FROM base AS gemini
USER root
RUN npm install -g @google/gemini-cli
USER agent
