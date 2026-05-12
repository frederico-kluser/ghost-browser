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
rm -rf /tmp/cbrowser-* /tmp/cfox-* /tmp/ghost-* 2>/dev/null || true

# -------- 4. pacotes apt (opcional) --------
# Só remove o que install.sh efetivamente instalou neste sistema. Isso evita
# desinstalar tor/curl/chromium que o usuário já tinha antes do ghost-browser.
TRACK="$HOME/.cache/ghost-browser/installed-pkgs"
echo
if [[ -f "$TRACK" ]]; then
    mapfile -t TRACKED < "$TRACK"
    if [[ ${#TRACKED[@]} -gt 0 ]]; then
        warn "Pacotes que install.sh instalou neste sistema:"
        warn "  ${TRACKED[*]}"
        read -r -p "Remover esses pacotes? [y/N] " RESP
        if [[ "${RESP,,}" =~ ^y(es)?$ ]]; then
            sudo systemctl disable --now tor 2>/dev/null || true
            sudo apt remove -y "${TRACKED[@]}"
            sudo apt autoremove -y
            # Se brave-browser estava na lista, install.sh também adicionou um repo apt
            # de terceiros que vale a pena limpar agora que não é mais necessário.
            if printf '%s\n' "${TRACKED[@]}" | grep -qx brave-browser; then
                info "Removendo repositório apt da Brave..."
                sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
                sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
                sudo apt update -qq 2>/dev/null || true
            fi
            rm -f "$TRACK"
            rmdir "$HOME/.cache/ghost-browser" 2>/dev/null || true
            info "Pacotes apt removidos."
        else
            info "Mantendo pacotes apt instalados."
        fi
    else
        info "Registro de pacotes está vazio — nada a remover via apt."
    fi
else
    warn "Sem registro em $TRACK (install.sh nunca rodou aqui, ou é versão antiga)."
    warn "Não removerei pacotes apt automaticamente para evitar tirar algo que você já tinha."
    warn "Se quiser remover manualmente: sudo apt remove tor"
fi

info "Uninstall concluído."
