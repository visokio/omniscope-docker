# Omniscope Docker (BYOL)

Public Dockerfiles and examples for Visokio Omniscope (Bring-Your-Own-License).

## Contents
- `Dockerfile` — builds Omniscope headless server (Ubuntu 22.04) running as non-root user `omniscope`.
- `entrypoint.sh` — production entrypoint handling license detection and first-run setup.
- `docker-compose.yml` — example stack with required mounts and hostname.

---

## Build locally

### 🔖 Important — Tag the Image With the Correct Omniscope Version

When you build the image, always tag it using the **exact Omniscope version** from the bundle URL you are using.

For example, if your bundle URL contains:

```
.../2026-1/22349/Bundles/VisokioOmniscope-Linux.tgz
```

Then your image **must** be tagged:

```
2026.1.22349
```

### Example
```bash
# Build using the correct version tag
docker build -t <repo>/omniscope:2026.1.22349 .

# Optionally also tag as 'latest' within your repo
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

docker run -d --name omniscope   --restart unless-stopped   -p 8080:8080   -h my-omniscope-server   -v "$PWD/omniscope-server":/home/omniscope/omniscope-server   -v "$PWD/license/omniscope.lic":/home/omniscope/.visokioappdata/Visokio/Omniscope/licenses/omniscope.lic:ro   -e CONTAINER_ID="$(hostname)"   <repo>/omniscope:2026.1.22349
```

Check logs:
```bash
docker logs omniscope | grep "One-time admin password"
```

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