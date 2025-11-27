# Omniscope Docker (BYOL)

Public Dockerfiles and examples for Visokio Omniscope (Bring-Your-Own-License).

## Contents
- `Dockerfile` — builds Omniscope headless server (Ubuntu 22.04) running as non-root user `omniscope`.
- `entrypoint.sh` — production entrypoint handling license detection and first-run setup.
- `docker-compose.yml` — example stack with required mounts and hostname.

## Build locally
```bash
# Build your own image (replace <repo> with your registry/namespace)
docker build -t <repo>/omniscope:2026.1.22349 .

# Optionally tag as latest within your repo
docker tag <repo>/omniscope:2026.1.22349 <repo>/omniscope:latest
```

## Run with Docker
```bash
mkdir -p omniscope-server license
cp /path/to/your.lic license/omniscope.lic
chmod 600 license/omniscope.lic

docker run -d --name omniscope \
  --restart unless-stopped \
  -p 8080:8080 \
  -h my-omniscope-server \
  -v "$PWD/omniscope-server":/home/omniscope/omniscope-server \
  -v "$PWD/license/omniscope.lic":/home/omniscope/.visokioappdata/Visokio/Omniscope/licenses/omniscope.lic:ro \
  -e CONTAINER_ID="$(hostname)" \
  <repo>/omniscope:2026.1.22349
```
Then check logs for the one-time admin password:
```bash
docker logs omniscope | grep "One-time admin password"
```

## Run with Docker Compose
```bash
docker compose up -d --force-recreate
```
Key bits in `docker-compose.yml`:
- Hostname: `my-omniscope-server`
- Mount config/projects: `./omniscope-server -> /home/omniscope/omniscope-server`
- Mount license dir: `./license -> /home/omniscope/.visokioappdata/Visokio/Omniscope/licenses:ro`
- Env: `CONTAINER_ID=${HOSTNAME}`


## Non-root user
The image runs as user `omniscope` with home `/home/omniscope`. All mounts and paths in the examples reflect this.
