#!/usr/bin/env bash
# uninstall.sh — remove venv Camoufox e (opcionalmente) pacotes instalados.
#
# Por padrão NÃO remove tor/chromium/etc., porque podem estar em uso por
# outros aplicativos. Pergunta interativamente antes de remover.
#
# Suporta Ubuntu/Debian (apt) e macOS (brew). S.O. detectado via lib/platform.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

OS_KIND="$(ghost_os)" || { warn "S.O. não suportado — abortando."; exit 1; }
info "S.O. detectado: $OS_KIND"

VENV="$HOME/.camoufox-venv"

# -------- 1. venv Camoufox --------
if [[ -d "$VENV" ]]; then
    info "Removendo venv Camoufox em $VENV..."
    rm -rf "$VENV"
else
    info "Nenhum venv Camoufox para remover."
fi

# -------- 2. cache do Camoufox (binário ~300MB) --------
# Múltiplos caminhos possíveis conforme S.O. (XDG no Linux, ~/Library no macOS).
while IFS= read -r CACHE_DIR; do
    if [[ -n "$CACHE_DIR" && -d "$CACHE_DIR" ]]; then
        info "Removendo cache binário do Camoufox em $CACHE_DIR..."
        rm -rf "$CACHE_DIR"
    fi
done < <(ghost_camoufox_cache_dirs)

# -------- 3. perfis temporários residuais --------
# Usa $TMPDIR no macOS (/var/folders/.../T) em vez de /tmp.
info "Limpando perfis temporários residuais..."
T="$(ghost_tmp_prefix)"
rm -rf "$T"/cbrowser-* "$T"/cfox-* "$T"/ghost-* 2>/dev/null || true
# Limpa também /tmp diretamente caso TMPDIR aponte pra outro lugar
rm -rf /tmp/cbrowser-* /tmp/cfox-* /tmp/ghost-* 2>/dev/null || true

# -------- 4. pacotes do sistema (opcional) --------
# Só remove o que install.sh efetivamente instalou neste sistema. Isso evita
# desinstalar tor/curl/chromium que o usuário já tinha antes do ghost-browser.
TRACK="$HOME/.cache/ghost-browser/installed-pkgs"
echo
if [[ -f "$TRACK" ]]; then
    # Bash 3.2 portable: while-read em vez de mapfile.
    TRACKED=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && TRACKED+=("$line")
    done < "$TRACK"

    if [[ ${#TRACKED[@]} -gt 0 ]]; then
        warn "Pacotes que install.sh instalou neste sistema:"
        warn "  ${TRACKED[*]}"
        read -r -p "Remover esses pacotes? [y/N] " RESP
        # Bash 3.2 portable: tr em vez de ${RESP,,}
        RESP_LOW="$(printf '%s' "$RESP" | tr '[:upper:]' '[:lower:]')"
        if [[ "$RESP_LOW" =~ ^y(es)?$ ]]; then

            # Separa entries por prefixo:
            #   pkg:foo     → pacote do package manager nativo (apt/pacman/dnf/brew formula)
            #   cask:foo    → macOS brew cask
            #   flatpak:foo → app Flatpak (escopo --user)
            #   wrapper:/p  → script wrapper criado em ~/.local/bin
            #   (sem prefixo) → legado, tratado como pkg:
            FORMULAE=()
            CASKS=()
            FLATPAKS=()
            WRAPPERS=()
            for entry in "${TRACKED[@]}"; do
                case "$entry" in
                    pkg:*)     FORMULAE+=("${entry#pkg:}") ;;
                    cask:*)    CASKS+=("${entry#cask:}") ;;
                    flatpak:*) FLATPAKS+=("${entry#flatpak:}") ;;
                    wrapper:*) WRAPPERS+=("${entry#wrapper:}") ;;
                    *)         FORMULAE+=("$entry") ;;
                esac
            done

            # Para a Tor antes de desinstalar (válido em ambos S.O.)
            ghost_service_disable tor

            if [[ ${#FORMULAE[@]} -gt 0 ]]; then
                info "Removendo pacotes (${OS_KIND}): ${FORMULAE[*]}"
                ghost_pkg_remove "${FORMULAE[@]}" || warn "alguma remoção falhou — verifique manualmente"
            fi

            if [[ ${#CASKS[@]} -gt 0 && "$OS_KIND" == "macos" ]]; then
                info "Removendo brew casks: ${CASKS[*]}"
                ghost_cask_uninstall "${CASKS[@]}" || warn "alguma remoção de cask falhou"
            fi

            if [[ ${#FLATPAKS[@]} -gt 0 ]]; then
                info "Removendo flatpaks (--user): ${FLATPAKS[*]}"
                for app in "${FLATPAKS[@]}"; do
                    flatpak uninstall --user -y "$app" 2>/dev/null \
                        || warn "flatpak uninstall $app falhou — tente manualmente"
                done
            fi

            if [[ ${#WRAPPERS[@]} -gt 0 ]]; then
                info "Removendo wrappers em ~/.local/bin: ${WRAPPERS[*]}"
                for w in "${WRAPPERS[@]}"; do rm -f "$w"; done
            fi

            # Cleanup Debian-specific: repo apt da Brave (criado pelo install.sh
            # quando foi rota sem-snap). Em Arch/Fedora não há repo terceiro
            # adicionado por nós, então o ghost_pkg_remove acima já bastou.
            DISTRO_NOW="$(ghost_linux_distro 2>/dev/null || echo other)"
            if [[ "$DISTRO_NOW" == "debian" ]] \
               && printf '%s\n' "${FORMULAE[@]}" | grep -qx brave-browser; then
                info "Removendo repositório apt da Brave..."
                sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
                sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
                sudo apt update -qq 2>/dev/null || true
            fi

            rm -f "$TRACK"
            rmdir "$HOME/.cache/ghost-browser" 2>/dev/null || true
            info "Pacotes removidos."
        else
            info "Mantendo pacotes instalados."
        fi
    else
        info "Registro de pacotes está vazio — nada a remover."
    fi
else
    warn "Sem registro em $TRACK (install.sh nunca rodou aqui, ou é versão antiga)."
    warn "Não removerei pacotes automaticamente para evitar tirar algo que você já tinha."
    case "$(ghost_pkg_manager 2>/dev/null)" in
        apt)    warn "Se quiser remover manualmente: sudo apt remove tor" ;;
        pacman) warn "Se quiser remover manualmente: sudo pacman -Rns tor" ;;
        dnf)    warn "Se quiser remover manualmente: sudo dnf remove tor" ;;
        brew)   warn "Se quiser remover manualmente: brew uninstall tor" ;;
    esac
fi

info "Uninstall concluído."
