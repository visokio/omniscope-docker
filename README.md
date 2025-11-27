# Omniscope Docker (BYOL)

Public Dockerfiles and examples for Visokio Omniscope (Bring-Your-Own-License).

## Contents
- `Dockerfile` — builds Omniscope headless server (Ubuntu 22.04) running as non-root user `omniscope`.
- `entrypoint.sh` — production entrypoint handling license detection and first-run setup.
- `docker-compose.yml` — example stack with required mounts and hostname.

---
## Build locally

### 🔖 Important — When to Tag the Image

Tagging with the Omniscope version is **only required when pushing the image to a registry** (Docker Hub, ECR, GitLab, etc.).  
If you are running the image **locally**, tagging with a version is optional.

### Local build (no version tag required)
```bash
docker build -t omniscope-local .
```

### Publishing to a registry (use the correct Omniscope version)

Find the version from the bundle URL, for example:

```
.../2026-1/22349/Bundles/VisokioOmniscope-Linux.tgz
```

This corresponds to:

```
2026.1.22349
```

### Example (for pushing)
```bash
# Build using the correct version tag
docker build -t <repo>/omniscope:2026.1.22349 .

# Optionally also tag as 'latest'
docker tag <repo>/omniscope:2026.1.22349 <repo>/omniscope:latest
```


---

## Using a Different Omniscope Version (Custom .tgz Bundle)

The Dockerfile contains:

```dockerfile
ARG linux_bundle=https://storage.googleapis.com/builds.visokio.com/<year>-<minor>/<build>/Bundles/VisokioOmniscope-Linux.tgz
```

To build with a different version, update this value.

### Option 1 — Override at build time
```bash
docker build   --build-arg linux_bundle="https://storage.googleapis.com/builds.visokio.com/2026-1/22349/Bundles/VisokioOmniscope-Linux.tgz"   -t <repo>/omniscope:2026.1.22349 .
```

### Option 2 — Edit Dockerfile directly
Change the `ARG linux_bundle=` line to your desired bundle URL.

> **Reminder:**  
> Always update your image tag to match the **year.minor.build** of the bundle you are using.

---

## Run with Docker

```bash
mkdir -p omniscope-server license
cp /path/to/your.lic license/omniscope.lic
chmod 600 license/omniscope.lic

# Choose the image tag:
# - Local-only: use the locally built image `omniscope-local` (see build section above).
# - Pushing/shared: use a versioned tag like `<repo>/omniscope:2026.1.22349`.
docker run -d \
  --name omniscope \
  --hostname my-omniscope-server \
  --restart unless-stopped \
  -p 8080:8080 \
  -e HOSTNAME=my-omniscope-server \
  -e CONTAINER_ID=my-omniscope-server \
  -v "$PWD/omniscope-server":/home/omniscope/omniscope-server \
  -v "$PWD/license/omniscope.lic":/home/omniscope/.visokioappdata/Visokio/Omniscope/licenses/omniscope.lic:ro \
  <repo>/omniscope:2026.1.22349
```

Check logs:
```bash
docker logs omniscope | grep -m1 -F "Admin password (save securely)"
```

### Finding and storing the admin password
- On first run Omniscope prints a admin password to stdout; fetch it with `docker logs omniscope | grep -m1 -F "Admin password (save securely)"` (or `docker compose logs omniscope | grep -m1 -F "Admin password (save securely)"` if using Compose).
- Copy the password to a secure location (e.g., your team password manager) immediately; avoid leaving it in shell history or plaintext files.

---

## Run with Docker Compose

```bash
docker compose up -d --force-recreate
```

Key mappings:
- ./omniscope-server → /home/omniscope/omniscope-server
- ./license → /home/omniscope/.visokioappdata/Visokio/Omniscope/licenses:ro

---

## Non-root user

The image runs as user `omniscope` with home directory `/home/omniscope`.

All volume mounts and examples reflect this path layout.
