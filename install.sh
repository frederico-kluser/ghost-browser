#!/usr/bin/env bash
# install.sh — instala dependências do ghost-browser de forma idempotente
#
# Instala:
#   - Tor (proxy SOCKS5 em 127.0.0.1:9050)
#   - Chromium (Caminho A)
#   - libs nativas requeridas por Camoufox
#   - venv Python com Camoufox + GeoIP (Caminho B)
#
# Pressupõe Ubuntu/Debian 22.04+. Para outras distros, adapte o gerenciador.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

VENV="$HOME/.camoufox-venv"

# -------- 1. pacotes apt --------
APT_PKGS=(
    tor
    chromium-browser
    curl
    jq
    netcat-openbsd
    python3-pip
    python3-venv
    libgtk-3-0
    libasound2
    libdbus-glib-1-2
    libx11-xcb1
)

MISSING=()
for pkg in "${APT_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Instalando pacotes apt: ${MISSING[*]}"
    sudo apt update
    sudo apt install -y "${MISSING[@]}"
else
    info "Todos os pacotes apt já estão instalados."
fi

# -------- 2. serviço Tor --------
if systemctl is-enabled --quiet tor 2>/dev/null; then
    info "Tor já habilitado."
else
    info "Habilitando serviço Tor..."
    sudo systemctl enable --now tor
fi

if ! systemctl is-active --quiet tor; then
    sudo systemctl start tor
fi

# -------- 3. venv Camoufox --------
if [[ -d "$VENV" ]]; then
    info "venv Camoufox já existe em $VENV — atualizando."
else
    info "Criando venv Camoufox em $VENV..."
    python3 -m venv "$VENV"
fi

# shellcheck source=/dev/null
source "$VENV/bin/activate"
pip install --quiet --upgrade pip
info "Instalando/atualizando camoufox[geoip]..."
pip install --quiet -U "camoufox[geoip]"

info "Baixando binário Camoufox + dataset GeoIP (pode levar ~3min, ~300MB)..."
python -m camoufox fetch
deactivate

# -------- 4. chmod nos scripts do projeto --------
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
info "Tornando scripts executáveis..."
chmod +x "$SCRIPT_DIR"/spoof-browser.sh \
          "$SCRIPT_DIR"/camoufox-spoof.sh \
          "$SCRIPT_DIR"/new-tor-circuit.sh \
          "$SCRIPT_DIR"/uninstall.sh 2>/dev/null || true

# -------- 5. validação final --------
info "Testando saída Tor:"
if curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://ipinfo.io/json | jq . 2>/dev/null; then
    info "Tor OK."
else
    warn "Não foi possível confirmar Tor (timeout/bloqueio?). Verifique 'systemctl status tor'."
fi

echo
info "Instalação concluída."
echo
echo "Exemplos:"
echo "  ./spoof-browser.sh windows-chrome"
echo "  ./camoufox-spoof.sh macos https://browserleaks.com"
echo "  USE_TOR=0 ./camoufox-spoof.sh linux"
