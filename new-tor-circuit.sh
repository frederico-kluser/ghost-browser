#!/usr/bin/env bash
# new-tor-circuit.sh — força o Tor a usar um novo circuito (novo IP de saída)
#
# Tenta primeiro a forma rápida (ControlPort 9051 + SIGNAL NEWNYM).
# Se ControlPort não estiver aberta, faz fallback para reload do serviço.
#
# Para habilitar ControlPort, edite o torrc adicionando:
#     ControlPort 9051
#     CookieAuthentication 0
# e reinicie o serviço.
#
# Caminho do torrc:
#   Linux : /etc/tor/torrc                       (depois: sudo systemctl restart tor)
#   macOS : $(brew --prefix)/etc/tor/torrc       (depois: brew services restart tor)
# No macOS, brew install tor cria apenas torrc.sample — copie-o antes de editar:
#   cp "$(brew --prefix)/etc/tor/torrc.sample" "$(brew --prefix)/etc/tor/torrc"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

OLD_IP="$(curl -s --max-time 8 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org || echo desconhecido)"
info "IP atual via Tor: $OLD_IP"

# -------- Caminho rápido: ControlPort --------
# Usa nc -z em vez de /dev/tcp porque o bash 3.2 do macOS não suporta /dev/tcp.
if ghost_port_open 127.0.0.1 9051; then
    info "ControlPort 9051 aberta — enviando SIGNAL NEWNYM..."
    printf 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc 127.0.0.1 9051 || true
else
    warn "ControlPort 9051 fechada — fazendo fallback para reload do serviço Tor (mais lento)."
    ghost_service_reload tor
fi

# Tor leva alguns segundos para fechar circuitos antigos e abrir novo
info "Aguardando novo circuito (5s)..."
sleep 5

NEW_IP="$(curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org || echo desconhecido)"
info "Novo IP via Tor: $NEW_IP"

if [[ "$OLD_IP" == "$NEW_IP" ]]; then
    warn "O IP não mudou. Tor reutiliza circuitos para o mesmo destino por ~10min."
    warn "Tente novamente em alguns segundos, ou reinicie o tor pelo seu init system."
fi
