# ==============================================================================
# Visokio Omniscope (BYOL, .lic-only)
# Ubuntu 22.04 base with MonetDB and Omniscope headless server
# Runs as non-root user "omniscope"
# ==============================================================================

FROM ubuntu:22.04

# ----------------------------------------------------------------------------
# Build-time arguments
# ----------------------------------------------------------------------------
ARG ubuntu_ver_code_name=jammy
ARG monetdb_ver=11.55.1
ARG linux_bundle=https://storage.googleapis.com/builds.visokio.com/2026-1/22370/Bundles/VisokioOmniscope-Linux.tgz

# Noninteractive APT to avoid tzdata prompts, etc.
ENV DEBIAN_FRONTEND=noninteractive

# Base paths
ENV OMNISCOPE_HOME=/home/omniscope
ENV OMNISCOPE_APP_DIR=${OMNISCOPE_HOME}/visokio-omniscope
ENV OMNISCOPE_SERVER_DIR=${OMNISCOPE_HOME}/omniscope-server
ENV OMNISCOPE_APPDATA_DIR=${OMNISCOPE_HOME}/.visokioappdata/Visokio/Omniscope

# ----------------------------------------------------------------------------
# System dependencies
# ----------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      # Basic tools
      ca-certificates \
      gnupg \
      wget \
      fontconfig \
      lsb-release \
      nano \
      # Python
      python3 \
      python3-pip \
      python3-venv \
      # R and Compilation Dependencies
      r-base \
      r-base-dev \
      build-essential \
      libcurl4-openssl-dev \
      libssl-dev \
      libxml2-dev \
      zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------------------------
# MonetDB (Ubuntu 22.04 "jammy") — version locked
# ----------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /usr/share/keyrings; \
    wget -qO /usr/share/keyrings/monetdb.gpg https://dev.monetdb.org/downloads/MonetDB-GPG-KEY.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/monetdb.gpg] https://dev.monetdb.org/downloads/deb/ ${ubuntu_ver_code_name} monetdb" > /etc/apt/sources.list.d/monetdb.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      monetdb5-sql=${monetdb_ver} \
      monetdb-client=${monetdb_ver}; \
    rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------------------------
# Create non-root user and base directories
# ----------------------------------------------------------------------------
RUN set -eux; \
    useradd -m -s /bin/bash omniscope; \
    mkdir -p "${OMNISCOPE_APP_DIR}" \
             "${OMNISCOPE_SERVER_DIR}" \
             "${OMNISCOPE_APPDATA_DIR}/licenses" \
             "${OMNISCOPE_APPDATA_DIR}/config"; \
    chown -R omniscope:omniscope "${OMNISCOPE_HOME}"

# Use non-root for application install/runtime
USER omniscope
WORKDIR /home/omniscope

# ----------------------------------------------------------------------------
# Fetch & unpack Omniscope
# ----------------------------------------------------------------------------
RUN set -eux; \
    wget -O /tmp/VisokioOmniscope-Linux.tgz "${linux_bundle}"; \
    tar -xzf /tmp/VisokioOmniscope-Linux.tgz -C "${OMNISCOPE_APP_DIR}" --strip-components=1 --no-same-owner; \
    rm -f /tmp/VisokioOmniscope-Linux.tgz; \
    chmod +x "${OMNISCOPE_APP_DIR}/omniscope-evo.sh" || true; \
    chmod +x "${OMNISCOPE_APP_DIR}/omniscope-evo-headless.sh" || true

# ----------------------------------------------------------------------------
# Entrypoint (outside main install directory)
# ----------------------------------------------------------------------------
COPY --chown=omniscope:omniscope entrypoint.sh /home/omniscope/entrypoint.sh
RUN chmod +x /home/omniscope/entrypoint.sh

# ----------------------------------------------------------------------------
# Networking & Health
# ----------------------------------------------------------------------------
EXPOSE 8080
# EXPOSE 8443  # Optional HTTPS (enable if configured in Omniscope)

# Health: process + TCP socket (works even if HTTP shows an auth dialog)
HEALTHCHECK --interval=15s --timeout=3s --retries=10 \
  CMD bash -lc 'pgrep -f "omniscope-evo-headless" >/dev/null && exec 3<>/dev/tcp/127.0.0.1/${OMNI_HTTP_PORT:-8080}'

# ----------------------------------------------------------------------------
# Entrypoint
# ----------------------------------------------------------------------------
ENTRYPOINT ["/home/omniscope/entrypoint.sh"]

# ----------------------------------------------------------------------------
# Notes
# ----------------------------------------------------------------------------
#  - Mount LICENSE DIRECTORY (any filename accepted) to:
#       /home/omniscope/.visokioappdata/Visokio/Omniscope/licenses
#  - Mount config folder to:
#       /home/omniscope/omniscope-server
#  - On first start, Omniscope prints a admin password in logs.
# ----------------------------------------------------------------------------
