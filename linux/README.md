# Triple X on Linux (Ubuntu, Debian and relatives)

One script installs and manages the whole stack — Monero node, P2Pool,
optional Tari merge-mining, wallets and the web dashboard — on a plain Linux
machine. It runs the same prebuilt, digest-pinned Docker images as the app-store
version, so there is no from-source build.

## Requirements

- Ubuntu 22.04+ / Debian 12+ (or Mint, Pop!_OS, Raspberry Pi OS 64-bit, …) on **x86_64**
- A user with `sudo`
- ~150 GB free disk for the pruned Monero blockchain (more if you remove pruning), 4 GB+ RAM
- Internet access (images come from `ghcr.io`)

Docker and Docker Compose are installed for you if they are missing.

## Install

```bash
git clone https://github.com/Silver765/Triple-X.git
cd Triple-X/linux
sudo ./triple-x.sh install
```

(No git? `curl -fsSLO https://raw.githubusercontent.com/Silver765/Triple-X/main/linux/triple-x.sh`
then `sudo bash triple-x.sh install` — it downloads the compose file itself.)

When it finishes it prints the dashboard address, e.g. `http://192.168.1.50:3000`.
Open it, set your payout address in **Settings**, and let `monerod` sync. Point
your miner (XMRig, etc.) at `<server-ip>:3333` — any username works, the pool
pays the address from Settings.

## Day-to-day

| Command | What it does |
|---|---|
| `triple-x status` | Container status and dashboard URL |
| `triple-x logs [service]` | Follow logs (`web`, `monerod`, `p2pool`, `minotari-node`, …) |
| `sudo triple-x update` | Fetch the newest published release and restart |
| `sudo triple-x stop` / `start` / `restart` | Control the stack |
| `sudo triple-x uninstall` | Remove containers, **keep your data** |
| `sudo triple-x uninstall --purge` | Also delete all data (blockchain, wallets, settings) — asks you to type `DELETE` |

Containers use `restart: unless-stopped`, so everything comes back after a
reboot as long as the Docker service is enabled (the installer does that).

## Where things live

- `/opt/triple-x/docker-compose.yml` and `.env`
- `/opt/triple-x/data/` — blockchain, wallets, P2Pool data, settings. **Back up
  the wallet seed phrases the dashboard shows you; they are shown once.**
- Change locations with `TRIPLE_X_DIR=/path` / `TRIPLE_X_DATA=/path` when running `install`.

## Ports

| Port | Use | Forward on router? |
|---|---|---|
| 3000 | Dashboard | **No** — LAN only |
| 3333 | Miner stratum | **No** — LAN only |
| 18080 | Monero p2p | Yes (better connectivity) |
| 37889 / 37888 / 37890 | P2Pool p2p (Standard / Mini / Nano) | Yes, for the pool type you use |
| 18189 | Tari p2p | Yes, if merge-mining Tari |

If `ufw` is active the installer opens these on the machine itself.

## Notes

- The dashboard's optional "Import Blockchain" feature uses the Docker socket
  and is off by default; see the note in the compose file.
- ARM boards (Raspberry Pi) need images built for arm64; the published ones are x86_64.
