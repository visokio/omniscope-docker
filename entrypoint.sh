#!/usr/bin/env bash
# ==============================================================================
# Visokio Omniscope (BYOL, .lic-only) — Production Entrypoint (Headless)
# ------------------------------------------------------------------------------
# Behavior:
#   - Requires a BYOL license mounted under the LICENSE DIRECTORY:
#       /home/omniscope/.visokioappdata/Visokio/Omniscope/licenses
#     (any non-empty file inside this directory is accepted; *.lic preferred)
#   - Runs autosetup when:
#       - First boot (no /home/omniscope/omniscope-server/config.xml), or
#       - OMNI_FORCE_CREATE_ADMIN_PWD=true
#   - Autosetup uses:  -autosetup xxxx "<ADMIN_PASSWORD>"
#   - Always prints the one-time admin password on first initialization.
#
# Env:
#   OMNI_FORCE_CREATE_ADMIN_PWD=true | false
#   OMNI_LICENSE_DIR                # optional override for license directory
#   OMNI_KB_URL                     # optional override for KB link shown on errors
# ==============================================================================
set -Eeuo pipefail

OMNI_HOME="/home/omniscope/visokio-omniscope"
SERVER_DIR="/home/omniscope/omniscope-server"
CONFIG_XML="${SERVER_DIR}/config.xml"

# License directory (accept any filename inside)
LIC_DIR="${OMNI_LICENSE_DIR:-/home/omniscope/.visokioappdata/Visokio/Omniscope/licenses}"

# Admin password (prefer Docker secret)
SECRET_PATH="/run/secrets/omni_admin_password"

# KB link for full setup (folders, env vars, K8s examples)
KB_URL="${OMNI_KB_URL:-https://help.visokio.com/support/solutions/articles/42000115297-setting-up-omniscope-byol-containers-folders-license-mounts-and-environment-variables-docker-compose-kubernetes-}"

FIRST_RUN_MARKER="${SERVER_DIR}/.first_run_done"
FIRST_INIT_FLAG="${SERVER_DIR}/.visokio_force_first_server_init_"

log(){ printf '[omni-entrypoint] %s\n' "$*"; }
err(){ printf '[omni-entrypoint] ERROR: %s\n' "$*" >&2; }

dump_logs_and_exit() {
  for f in startup.log server.log install.log; do
    [[ -f "${SERVER_DIR}/logs/$f" ]] && { echo "---- ${f} ----"; tail -n 200 "${SERVER_DIR}/logs/$f" || true; }
  done
  exit 1
}
trap 'err "Entrypoint failed"; dump_logs_and_exit' ERR
[[ "${DEBUG:-}" == "true" ]] && set -x

# ------------------------------------------------------------------------------
# 1) License discovery (.lic-only; accept ANY non-empty file in ${LIC_DIR})
# ------------------------------------------------------------------------------
_find_license_file() {
  local f
  # Prefer *.lic (case-insensitive), else any non-empty regular file
  f="$(find -L "${LIC_DIR}" -maxdepth 1 -type f -iname '*.lic' -size +0c 2>/dev/null | head -n1 || true)"
  [[ -n "$f" ]] || f="$(find -L "${LIC_DIR}" -maxdepth 1 -type f -size +0c 2>/dev/null | head -n1 || true)"
  printf '%s' "$f"
}

LIC_FILE="$(_find_license_file || true)"
if [[ -z "${LIC_FILE}" ]]; then
  cat >&2 <<EOF

----------------------------------------------------------------------
[Omniscope BYOL] No license file detected.

[INFO] Follow the setup guide:
       ${KB_URL}

WHAT YOU NEED TO DO (SUMMARY)
STEP 1: Prepare folders on the host:
        mkdir -p ./license ./omniscope-server
        # place your .lic file (any filename) into ./license/

STEP 2: Mount ./license into the container as read-only:
        -v "\$PWD/license":${LIC_DIR}:ro

STEP 3: Provide identity variables:
        - Docker/Compose:
            -e CONTAINER_ID="\$(hostname)"
            -h my-omniscope-server   # sets a readable container hostname
        - Kubernetes:
            - CONTAINER_ID -> metadata.uid
            - CLUSTER_ID   -> ConfigMap key (true cluster ID)

STEP 4: Start the container and check logs for the one-time admin password.

QUICK EXAMPLES

- Docker (directory mount; host ./license -> container licenses)
  docker run -d --name omniscope \
    -h my-omniscope-server \
    -p 8080:8080 \
    -v "\$PWD/omniscope-server":/home/omniscope/omniscope-server \
    -v "\$PWD/license":${LIC_DIR}:ro \
    -e CONTAINER_ID="\$(hostname)" \
    visokio/omniscope:latest

- Docker Compose (service: omniscope)
  volumes:
    - ./omniscope-server:/home/omniscope/omniscope-server
    - ./license/:${LIC_DIR}:ro
  environment:
    CONTAINER_ID: "\${HOSTNAME}"
    # CLUSTER_ID: "compose-local"  # optional placeholder
  hostname: my-omniscope-server

- Kubernetes (env only; see KB for full Deployment + PVC + volumeMounts)
  env:
    - name: CONTAINER_ID
      valueFrom: { fieldRef: { fieldPath: metadata.uid } }
    - name: HOSTNAME
      valueFrom: { fieldRef: { fieldPath: metadata.name } }
    - name: CLUSTER_ID
      valueFrom:
        configMapKeyRef: { name: cluster-identity, key: CLUSTER_ID }

IF YOU DON'T YET HAVE A LICENSE
  docker exec -it omniscope bash
  cd /home/omniscope/visokio-omniscope
  ./omniscope-evo-headless.sh -autosendbugreport=youremail@example.com
Then email support@visokio.com with the printed ID.
----------------------------------------------------------------------

EOF
  # EX_USAGE (64) -> clear "setup required" signal; avoids restart loops
  exit 64
fi
log "License file detected at: ${LIC_FILE}"

# ------------------------------------------------------------------------------
# 2) Ensure server dir exists and drop first-init marker if EMPTY
# ------------------------------------------------------------------------------
install -d -m 755 "${SERVER_DIR}" || true
if [ -z "$(ls -A "${SERVER_DIR}" 2>/dev/null)" ]; then
  : > "${FIRST_INIT_FLAG}"
  log "Created first-run marker (Omniscope will delete it on first init): ${FIRST_INIT_FLAG}"
fi

# ------------------------------------------------------------------------------
# 3) Decide if autosetup is needed
# ------------------------------------------------------------------------------
need_autosetup=false
[[ ! -f "${CONFIG_XML}" ]] && need_autosetup=true
[[ "${OMNI_FORCE_CREATE_ADMIN_PWD:-false}" == "true" ]] && need_autosetup=true

# ------------------------------------------------------------------------------
# 4) Resolve admin password (secret -> env -> generate)
# ------------------------------------------------------------------------------
OMNI_ADMIN_PASSWORD=""

gen_pwd() {
  # UUID-based generator, no /dev/* dependencies
  LC_ALL=C cat /proc/sys/kernel/random/uuid /proc/sys/kernel/random/uuid 2>/dev/null \
    | tr -d '-' \
    | head -c 20
}

resolve_admin_password() {
  if [[ -s "${SECRET_PATH}" ]]; then
    OMNI_ADMIN_PASSWORD="$(cat "${SECRET_PATH}")"
    log "Admin password loaded from Docker secret."
    return
  fi
  if [[ -n "${OMNI_ADMIN_PASSWORD:-}" ]]; then
    log "Admin password loaded from OMNI_ADMIN_PASSWORD env."
    return
  fi
  # Only auto-generate on first boot or forced run
  if [[ "${need_autosetup}" == "true" ]]; then
    OMNI_ADMIN_PASSWORD="$(gen_pwd || true)"
    if [[ -z "${OMNI_ADMIN_PASSWORD}" ]]; then
      err "Failed to generate admin password."
      exit 1
    fi
    log "Generated one-time admin password."
    return
  fi
}

# ------------------------------------------------------------------------------
# 5) Autosetup (if needed): -autosetup xxxx "<ADMIN_PASSWORD>"
# ------------------------------------------------------------------------------
if [[ "${need_autosetup}" == "true" ]]; then
  install -d -m 755 "${SERVER_DIR}" || true
  resolve_admin_password
  export OMNI_ADMIN_PASSWORD

  log "Running headless autosetup..."
  "${OMNI_HOME}/omniscope-evo-headless.sh" -autosetup xxxx "${OMNI_ADMIN_PASSWORD}"

  touch "${FIRST_RUN_MARKER}" 2>/dev/null || true

  log "Autosetup complete."
  log "=============================================================="
  log " One-time admin password (save securely): ${OMNI_ADMIN_PASSWORD}"
  log "=============================================================="
else
  log "Using existing configuration (no autosetup)."
fi

# ------------------------------------------------------------------------------
# 6) Start Omniscope (headless)
# ------------------------------------------------------------------------------
log "Starting Omniscope (headless)..."
exec "${OMNI_HOME}/omniscope-evo-headless.sh"
