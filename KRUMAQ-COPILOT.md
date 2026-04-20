# KRUMAQ-COPILOT — Personal Standalone AI & Private Cloud

Your own AI assistant, fully self-hosted. No subscriptions, no cloud fees, no data leaving your machine.

---

## 🖥️ Hardware Requirements

### Minimum viable setup (~$300–500 used/refurbished)

| Component | Specification |
|-----------|--------------|
| CPU | Intel i7/i9 (10th gen+) or AMD Ryzen 7/9 — 8+ cores |
| RAM | 32 GB DDR4 (64 GB recommended) |
| GPU | NVIDIA RTX 3060 **12 GB VRAM** or RTX 4060 Ti 16 GB |
| Storage | 1 TB NVMe SSD (OS + models) + 2 TB HDD (data) |
| Network | Gigabit Ethernet |

> **Why a GPU with 12+ GB VRAM?** Local LLMs are loaded entirely into GPU memory. A 12 GB card runs 7B–13B parameter models comfortably. 24 GB lets you run 70B models.

### Better long-term setup (~$1,000–2,000)

| Component | Specification |
|-----------|--------------|
| GPU | NVIDIA RTX 4090 (24 GB VRAM) |
| RAM | 128 GB DDR5 |
| Storage | 2 TB NVMe SSD |
| Alternative | Used Dell Precision / HP Z-series workstation + GPU upgrade |

---

## 🏗️ Architecture

```
[Your Devices] ──Tailscale VPN──► [Your Home Server]
                                        │
                              ┌─────────▼─────────┐
                              │   Docker Stack     │
                              │  ┌─────────────┐  │
                              │  │   Ollama    │  │  ← LLM backend (port 11434)
                              │  └─────────────┘  │
                              │  ┌─────────────┐  │
                              │  │  Open WebUI │  │  ← Web chat UI (port 8080)
                              │  └─────────────┘  │
                              │  ┌─────────────┐  │
                              │  │    Caddy    │  │  ← HTTPS reverse proxy (443)
                              │  └─────────────┘  │
                              └───────────────────┘
```

---

## 🚀 Quick Start

### 1. Prepare your server

Install **Ubuntu Server 22.04 LTS** or **Debian 12** on your dedicated machine.

### 2. Install Docker

```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
newgrp docker
```

### 3. Clone this repository

```bash
git clone https://github.com/XavierMP14/copilot-cli.git
cd copilot-cli
```

### 4. Configure your environment

```bash
cp .env.example .env
nano .env   # edit WEBUI_SECRET_KEY, WEBUI_URL, KRUMAQ_DOMAIN
```

### 5. Start the stack

```bash
docker compose up -d
```

### 6. Pull an AI model

```bash
# General purpose (recommended to start)
docker exec -it krumaq-ollama ollama pull llama3.2

# Code-focused (similar to GitHub Copilot)
docker exec -it krumaq-ollama ollama pull deepseek-coder

# Fast & lightweight (low-RAM machines)
docker exec -it krumaq-ollama ollama pull phi3

# Best quality (requires 24 GB+ VRAM)
docker exec -it krumaq-ollama ollama pull llama3.2:70b
```

### 7. Open the web UI

Visit `https://krumaq.localhost` (or your configured domain) in your browser.

---

## 💻 CLI Installation

Install the `krumaq` terminal interface on any machine on your network:

```bash
curl -fsSL https://raw.githubusercontent.com/XavierMP14/copilot-cli/main/krumaq-install.sh | bash
```

Point it at your server:

```bash
export KRUMAQ_HOST="http://192.168.1.50:11434"  # replace with your server IP
krumaq "explain Docker networking"
```

Or add it permanently to your shell profile (`~/.bashrc`, `~/.zshrc`):

```bash
echo 'export KRUMAQ_HOST="http://192.168.1.50:11434"' >> ~/.bashrc
```

### CLI usage

```
krumaq                                 # interactive chat (REPL)
krumaq "write a Dockerfile for Node"   # one-shot prompt
krumaq --model deepseek-coder "refactor: $(cat app.py)"
krumaq --list                          # list available models
krumaq --pull mistral                  # pull a model
krumaq --help                          # full help
```

---

## 🌐 Remote Access (no open ports)

### Option A — Tailscale (recommended)

1. [Sign up for Tailscale](https://tailscale.com) — free for up to 3 users / 100 devices
2. Install on your server: `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`
3. Install on your laptop/phone
4. Access KRUMAQ-COPILOT via your Tailscale hostname, e.g. `https://my-server.tail1234.ts.net`

### Option B — Cloudflare Tunnel (public HTTPS, no port forwarding)

1. [Create a free Cloudflare account](https://cloudflare.com)
2. Install `cloudflared`: `curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo apt-key add -`
3. `cloudflared tunnel login && cloudflared tunnel create krumaq`
4. Route your domain: `cloudflared tunnel route dns krumaq krumaq.yourdomain.com`
5. Run: `cloudflared tunnel run krumaq`

### Option C — DuckDNS (free dynamic DNS)

1. Visit [duckdns.org](https://www.duckdns.org) and create a free subdomain
2. Set up auto-update: `echo "url=\"https://www.duckdns.org/update?domains=YOUR_DOMAIN&token=YOUR_TOKEN&ip=\" | curl -o ~/duckdns/duck.log -K -" | crontab -`
3. Forward ports 80 and 443 on your router to your server
4. Update `KRUMAQ_DOMAIN` in `.env` to your DuckDNS subdomain

---

## 🔧 Nginx Alternative

If you prefer Nginx over Caddy, replace the `caddy` service in `docker-compose.yml` with:

```yaml
nginx:
  image: nginx:stable-alpine
  container_name: krumaq-nginx
  restart: unless-stopped
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ./nginx/certs:/etc/nginx/certs:ro
```

Then generate a self-signed certificate for LAN use:

```bash
mkdir -p nginx/certs
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout nginx/certs/krumaq.key \
  -out nginx/certs/krumaq.crt \
  -subj "/CN=krumaq.localhost"
```

---

## 🎛️ GPU Support (NVIDIA)

1. Install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
2. Uncomment the `deploy` block in `docker-compose.yml` under the `ollama` service:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

3. Restart: `docker compose up -d`
4. Verify GPU is used: `docker exec -it krumaq-ollama ollama ps`

---

## 🧠 Fine-Tuning (Optional)

Personalise a model with your own documents or coding style using [Unsloth](https://github.com/unslothai/unsloth) — free, runs on consumer GPUs:

```bash
pip install unsloth
# Follow Unsloth's notebook examples to fine-tune Llama or Mistral
# Then import the result into Ollama via a Modelfile
```

---

## 💰 Cost Summary

| Item | Cost |
|------|------|
| Hardware (one-time) | $300 – $2,000 |
| Electricity (~100 W server, 24/7) | ~$7 – $12 / month |
| Software stack | **$0** |
| Cloud / hosting fees | **$0** |
| Domain (optional) | **$0** with DuckDNS or Tailscale |

**Total ongoing cost: ~$7–12/month in electricity only.**

---

## 📦 File Overview

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Full stack deployment (Ollama + Open WebUI + Caddy) |
| `caddy/Caddyfile` | HTTPS reverse proxy configuration |
| `nginx/nginx.conf` | Nginx alternative reverse proxy |
| `krumaq` | CLI wrapper script |
| `krumaq-install.sh` | One-line CLI installer |
| `.env.example` | Environment variable template |

---

## 🔄 Updates

```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d

# Update the CLI
curl -fsSL https://raw.githubusercontent.com/XavierMP14/copilot-cli/main/krumaq-install.sh | bash
```

---

## 🆘 Troubleshooting

**Ollama not reachable:**
```bash
docker compose logs ollama
docker compose restart ollama
```

**Out of VRAM / model too slow:**
```bash
# Switch to a smaller model
krumaq --pull phi3
export KRUMAQ_MODEL=phi3
```

**Web UI not loading:**
```bash
docker compose logs open-webui caddy
```
