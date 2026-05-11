#!/usr/bin/env bash
# new-tor-circuit.sh — força o Tor a usar um novo circuito (novo IP de saída)
#
# Tenta primeiro a forma rápida (ControlPort 9051 + SIGNAL NEWNYM).
# Se ControlPort não estiver aberta, faz fallback para systemctl reload tor.
#
# Para habilitar ControlPort, edite /etc/tor/torrc adicionando:
#     ControlPort 9051
#     CookieAuthentication 0
# e reinicie: sudo systemctl restart tor

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

OLD_IP="$(curl -s --max-time 8 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org || echo desconhecido)"
info "IP atual via Tor: $OLD_IP"

# -------- Caminho rápido: ControlPort --------
if (echo > /dev/tcp/127.0.0.1/9051) 2>/dev/null; then
    info "ControlPort 9051 aberta — enviando SIGNAL NEWNYM..."
    printf 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc 127.0.0.1 9051 || true
else
    warn "ControlPort 9051 fechada — fazendo fallback para 'systemctl reload tor' (mais lento)."
    sudo systemctl reload tor
fi

# Tor leva alguns segundos para fechar circuitos antigos e abrir novo
info "Aguardando novo circuito (5s)..."
sleep 5

NEW_IP="$(curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org || echo desconhecido)"
info "Novo IP via Tor: $NEW_IP"

if [[ "$OLD_IP" == "$NEW_IP" ]]; then
    warn "O IP não mudou. Tor reutiliza circuitos para o mesmo destino por ~10min."
    warn "Tente novamente em alguns segundos, ou reinicie o tor: 'sudo systemctl restart tor'."
fi
