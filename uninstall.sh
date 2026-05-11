#!/usr/bin/env bash
# uninstall.sh — remove venv Camoufox e (opcionalmente) pacotes apt
#
# Por padrão NÃO remove tor/chromium/etc., porque podem estar em uso por
# outros aplicativos. Pergunta interativamente antes de remover.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

VENV="$HOME/.camoufox-venv"

# -------- 1. venv Camoufox --------
if [[ -d "$VENV" ]]; then
    info "Removendo venv Camoufox em $VENV..."
    rm -rf "$VENV"
else
    info "Nenhum venv Camoufox para remover."
fi

# -------- 2. cache do Camoufox (binário ~300MB) --------
CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/camoufox"
if [[ -d "$CACHE_DIR" ]]; then
    info "Removendo cache binário do Camoufox em $CACHE_DIR..."
    rm -rf "$CACHE_DIR"
fi

# -------- 3. perfis temporários residuais --------
info "Limpando perfis temporários residuais..."
rm -rf /tmp/cbrowser-* /tmp/cfox-* 2>/dev/null || true

# -------- 4. pacotes apt (opcional) --------
echo
warn "Por padrão NÃO removo pacotes apt (tor, chromium-browser, etc.)"
warn "porque outros apps podem depender deles."
read -r -p "Remover também os pacotes apt deste projeto? [y/N] " RESP
if [[ "${RESP,,}" == "y" || "${RESP,,}" == "yes" ]]; then
    sudo systemctl disable --now tor 2>/dev/null || true
    sudo apt remove -y tor chromium-browser
    sudo apt autoremove -y
    info "Pacotes apt removidos."
else
    info "Mantendo pacotes apt instalados."
fi

info "Uninstall concluído."
