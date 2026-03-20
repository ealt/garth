FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ARG GARTH_FEATURE_PACKAGES=""

RUN set -eux; \
  packages="bash ca-certificates curl git jq openssl python3 python3-pip gnupg"; \
  feature_packages="${GARTH_FEATURE_PACKAGES:-}"; \
  old_ifs="$IFS"; \
  IFS=','; \
  for pkg in $feature_packages; do \
    [ -n "$pkg" ] || continue; \
    case "$pkg" in \
      uv|bun) ;; \
      *) packages="$packages $pkg" ;; \
    esac; \
  done; \
  IFS="$old_ifs"; \
  apt-get update; \
  apt-get install -y --no-install-recommends $packages; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  feature_packages=",${GARTH_FEATURE_PACKAGES:-},"; \
  case "$feature_packages" in \
    *,uv,*) curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh ;; \
  esac; \
  case "$feature_packages" in \
    *,bun,*) \
      apt-get update; \
      apt-get install -y --no-install-recommends unzip; \
      rm -rf /var/lib/apt/lists/*; \
      curl -fsSL https://bun.sh/install | env BUN_INSTALL=/usr/local bash ;; \
  esac

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash agent

# Git credential helper reads GitHub token from mounted file.
RUN set -eux; \
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'token_file="${GARTH_GITHUB_TOKEN_FILE:-/run/garth/github_token}"' \
    'token=""' \
    'if [[ -f "$token_file" ]]; then' \
    '  token="$(cat "$token_file")"' \
    'fi' \
    'echo "protocol=https"' \
    'echo "host=github.com"' \
    'echo "username=x-access-token"' \
    'echo "password=$token"' \
    > /usr/local/bin/garth-git-credential-helper; \
  chmod +x /usr/local/bin/garth-git-credential-helper

RUN git config --system credential.helper /usr/local/bin/garth-git-credential-helper

# Export GITHUB_TOKEN from mounted token file so gh CLI (and other tools that
# read the env var) can authenticate.  Sourced on every login-shell startup
# (bash -lc), which means token rotations are picked up by new shell invocations.
RUN printf '%s\n' \
    'token_file="${GARTH_GITHUB_TOKEN_FILE:-/run/garth/github_token}"' \
    'if [ -f "$token_file" ]; then' \
    '  GITHUB_TOKEN="$(cat "$token_file")"' \
    '  export GITHUB_TOKEN' \
    'fi' \
    > /etc/profile.d/garth-gh-token.sh

USER agent
WORKDIR /home/agent

FROM base AS claude
ENV PATH="/home/agent/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
RUN set -eux; \
  native_bin="$(readlink -f /home/agent/.local/bin/claude)"; \
  install -m 0755 "$native_bin" /usr/local/bin/claude
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
