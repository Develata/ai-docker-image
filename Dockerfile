# syntax=docker/dockerfile:1.7
FROM debian:stable-slim

ARG AGENT_UID=1000
ARG AGENT_GID=1000
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates coreutils curl diffutils findutils gawk git gnupg \
    grep gzip iproute2 jq less libgcc-s1 libstdc++6 nano netcat-openbsd \
    openssh-client openssh-server patch procps ripgrep rsync sed tar tmux \
    unzip util-linux xz-utils \
 && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* \
 && groupadd --gid "${AGENT_GID}" agent \
 && useradd --uid "${AGENT_UID}" --gid "${AGENT_GID}" \
      --create-home --shell /bin/bash --password '*' agent \
 && install -d -m 0755 /run/sshd /usr/local/share/agent-image \
      /opt/agent-tools

COPY scripts/tools-update.sh /usr/local/bin/agent-tools-update
COPY scripts/agent-cli.sh /usr/local/bin/agent-cli
COPY scripts/entrypoint.sh /usr/local/bin/agent-entrypoint
COPY config/sshd_config /etc/ssh/agent_sshd_config
COPY config/agent-profile.sh /etc/profile.d/agent.sh
COPY custom/install.sh /usr/local/share/agent-image/custom-install.sh
RUN chmod 0755 /usr/local/bin/agent-* \
 && for name in claude codex bun bunx; do \
      ln -s agent-cli "/usr/local/bin/${name}"; \
    done \
 && agent-tools-update all \
 && for name in node npm; do \
      if command -v "$name" >/dev/null 2>&1; then \
        echo "Unexpected default dependency: $name" >&2; exit 1; \
      fi; \
    done \
 && /bin/bash -euo pipefail /usr/local/share/agent-image/custom-install.sh \
 && if command -v sudo >/dev/null 2>&1; then \
      echo "This image does not permit sudo." >&2; exit 1; \
    fi \
 && rm -rf /var/lib/apt/lists/* \
 && dpkg-query -W -f='${Package}\t${Version}\n' \
      > /usr/local/share/agent-image/debian-packages.tsv \
 && sha256sum /usr/local/share/agent-image/custom-install.sh \
      > /usr/local/share/agent-image/custom-hook.sha256 \
 && jq -s '{tools: ., builtAt: (now | todate)}' \
      /opt/agent-tools/{claude,codex,bun}/installed.json \
      > /usr/local/share/agent-image/build-manifest.json \
 && chown -R agent:agent /opt/agent-tools /home/agent

ENV HOME=/home/agent \
    CODEX_HOME=/home/agent/.codex \
    BUN_INSTALL=/home/agent/.bun \
    DISABLE_AUTOUPDATER=1 \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:/home/agent/.bun/bin:/home/agent/.local/bin \
    LANG=C.UTF-8
USER agent
WORKDIR /workspaces
EXPOSE 2222
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
CMD ["sshd"]
