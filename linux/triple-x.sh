#!/usr/bin/env bash
# Triple X - Linux installer / manager for Ubuntu, Debian and relatives
# (Linux Mint, Pop!_OS, Raspberry Pi OS, ...).
#
#   sudo ./triple-x.sh install     install Docker if needed, fetch + start everything
#   sudo triple-x update           pull the newest published images and restart
#   sudo triple-x start|stop|restart
#        triple-x status           container status + dashboard URL
#        triple-x logs [service]   follow logs (web, monerod, p2pool, ...)
#   sudo triple-x uninstall        stop and remove containers (keeps your data)
#   sudo triple-x uninstall --purge   ...and DELETE all data (blockchain, wallets!)
#
# It runs the exact same prebuilt, digest-pinned images the app-store version
# uses (ghcr.io/silver765/triple-x-*), so there is no from-source build: the
# first start just downloads images and then monerod syncs the blockchain.

set -euo pipefail

INSTALL_DIR="${TRIPLE_X_DIR:-/opt/triple-x}"
DATA_DIR="${TRIPLE_X_DATA:-$INSTALL_DIR/data}"
REPO_RAW="${TRIPLE_X_RAW:-https://raw.githubusercontent.com/Silver765/Triple-X/main}"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
PROJECT="triple-x"
BIN="/usr/local/bin/triple-x"

say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "this command needs root - re-run with sudo."
}

# docker compose v2 plugin (preferred) or the standalone docker-compose.
compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "$INSTALL_DIR/.env" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "$INSTALL_DIR/.env" "$@"
  else
    die "Docker Compose not found. Run: sudo triple-x install"
  fi
}

check_os() {
  [ "$(uname -s)" = "Linux" ] || die "this installer is for Linux only."
  local id="" like=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"; like="${ID_LIKE:-}"
  fi
  case " $id $like " in
    *" ubuntu "*|*" debian "*) ;;
    *) say "Not Ubuntu/Debian-based (${id:-unknown}) - continuing, but Docker must already be installed." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *) say "CPU is $(uname -m): the published images are built for x86_64 (amd64) and may not run here." ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && { docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; }; then
    ok "Docker and Compose already installed."
    return
  fi
  command -v apt-get >/dev/null 2>&1 || die "Docker/Compose missing and apt-get not found - install Docker Engine + Compose, then re-run."
  say "Installing Docker from your distribution's packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl docker.io
  if ! docker compose version >/dev/null 2>&1; then
    # Package name differs by release: docker-compose-v2 (Ubuntu 22.04+),
    # docker-compose-plugin (Docker's own repo), docker-compose (older/Debian).
    apt-get install -y docker-compose-v2 2>/dev/null \
      || apt-get install -y docker-compose-plugin 2>/dev/null \
      || apt-get install -y docker-compose
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  docker info >/dev/null 2>&1 || die "Docker installed but the daemon is not running (try: sudo systemctl start docker)."
  ok "Docker is ready."
}

# Use the compose file from this checkout if the script sits in a clone of the
# repo, otherwise download the current one (its image digests are re-pinned on
# every release, so main always points at the latest published build).
fetch_compose() {
  local here sibling
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  sibling="$here/../TripleX-triple-x/docker-compose.yml"
  mkdir -p "$INSTALL_DIR"
  if [ -r "$sibling" ] && [ "${TRIPLE_X_ONLINE:-0}" != "1" ]; then
    cp "$sibling" "$COMPOSE_FILE"
    ok "Using compose file from this checkout."
  else
    say "Downloading the latest compose file..."
    curl -fsSL "$REPO_RAW/TripleX-triple-x/docker-compose.yml" -o "$COMPOSE_FILE.tmp" \
      || die "could not download $REPO_RAW/TripleX-triple-x/docker-compose.yml"
    mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"
    ok "Downloaded."
  fi
  grep -q '@sha256:' "$COMPOSE_FILE" || die "compose file has no pinned image digests - refusing to use it."
}

write_env() {
  mkdir -p "$DATA_DIR"
  printf 'APP_DATA_DIR=%s\n' "$DATA_DIR" > "$INSTALL_DIR/.env"
}

lan_ip() {
  { hostname -I 2>/dev/null | awk '{print $1}'; } || true
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    say "ufw is active - opening Triple X ports..."
    ufw allow 3000/tcp comment 'Triple X dashboard' >/dev/null
    ufw allow 3333/tcp comment 'P2Pool stratum (miners)' >/dev/null
    ufw allow 18080/tcp comment 'Monero p2p' >/dev/null
    ufw allow 37888:37890/tcp comment 'P2Pool p2p' >/dev/null
    ufw allow 18189/tcp comment 'Tari p2p' >/dev/null
    ok "ufw rules added (dashboard port 3000 is open to your LAN - do not forward it on your router)."
  fi
}

cmd_install() {
  need_root
  check_os
  install_docker
  fetch_compose
  write_env
  open_firewall
  # Keep a copy of this script as the `triple-x` command.
  [ "$(readlink -f "${BASH_SOURCE[0]}")" = "$BIN" ] || install -m 0755 "${BASH_SOURCE[0]}" "$BIN"
  say "Downloading images and starting Triple X (first run can take several minutes)..."
  compose pull
  compose up -d
  local ip; ip="$(lan_ip)"
  echo
  ok "Triple X is running."
  echo "   Dashboard:  http://${ip:-<server-ip>}:3000"
  echo "   Miner URL:  ${ip:-<server-ip>}:3333   (shown on the dashboard's Pool tab too)"
  echo "   Data:       $DATA_DIR"
  echo "   Manage:     triple-x status | logs | update | stop | start"
  echo
  echo "Open the dashboard, set your payout address in Settings, and let monerod sync."
  echo "For better connectivity, forward TCP 18080 (Monero), 37889/37888/37890 (P2Pool) and"
  echo "18189 (Tari) on your router. Never forward 3000 or 3333 to the internet."
}

cmd_update() {
  need_root
  [ -f "$COMPOSE_FILE" ] || die "not installed - run: sudo ./triple-x.sh install"
  TRIPLE_X_ONLINE=1 fetch_compose
  say "Pulling new images..."
  compose pull
  compose up -d --remove-orphans
  ok "Updated. Old images can be cleaned with: docker image prune"
}

cmd_status() {
  [ -f "$COMPOSE_FILE" ] || die "not installed."
  compose ps
  local ip; ip="$(lan_ip)"
  echo; echo "Dashboard: http://${ip:-localhost}:3000"
}

cmd_uninstall() {
  need_root
  [ -f "$COMPOSE_FILE" ] || die "not installed."
  say "Stopping and removing containers..."
  compose down --remove-orphans
  if [ "${1:-}" = "--purge" ]; then
    printf 'This DELETES %s (blockchain, wallets, seed files, settings). Type DELETE to confirm: ' "$DATA_DIR"
    read -r answer
    [ "$answer" = "DELETE" ] || die "not confirmed - data kept."
    rm -rf "$DATA_DIR" "$INSTALL_DIR"
    rm -f "$BIN"
    ok "Removed everything."
  else
    ok "Containers removed. Your data is still in $DATA_DIR (use --purge to delete it)."
  fi
}

case "${1:-}" in
  install)   cmd_install ;;
  update)    cmd_update ;;
  start)     need_root; compose up -d ;;
  stop)      need_root; compose stop ;;
  restart)   need_root; compose restart ;;
  status)    cmd_status ;;
  logs)      shift; compose logs -f --tail=100 "$@" ;;
  uninstall) shift; cmd_uninstall "${1:-}" ;;
  *)
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
