#!/usr/bin/env bash
# install.sh — instala dependências do ghost-browser de forma idempotente
#
# Instala:
#   - Tor (proxy SOCKS5 em 127.0.0.1:9050)
#   - Chromium-family browser (Caminho A)
#   - libs nativas requeridas por Camoufox (apenas Linux)
#   - venv Python com Camoufox + GeoIP (Caminho B)
#
# Suporta Ubuntu/Debian 22.04+ (apt) e macOS 13+ (Homebrew obrigatório).
# S.O. detectado automaticamente via lib/platform.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

OS_KIND="$(ghost_os)" || { err "S.O. não suportado."; exit 1; }
info "S.O. detectado: $OS_KIND"
if [[ "$OS_KIND" == "macos" ]]; then
    ghost_require_brew || exit 1
fi

VENV="$HOME/.camoufox-venv"
PKG_TRACK_DIR="$HOME/.cache/ghost-browser"
PKG_TRACK_FILE="$PKG_TRACK_DIR/installed-pkgs"

# -------- tracking para o resumo final --------
INSTALLED=()  # coisas efetivamente instaladas/criadas nesta execução
SKIPPED=()    # coisas que já estavam presentes
FAILED=()     # coisas que falharam ou requerem ação manual

# -------- 1. pacotes do sistema --------
# Garante o diretório de tracking; uninstall.sh lê dele para remover só o que
# install.sh efetivamente instalou neste sistema.
mkdir -p "$PKG_TRACK_DIR"

if [[ "$OS_KIND" == "linux" ]]; then

    # Retorna o primeiro candidato que existe como pacote real (não virtual stub).
    # Necessário porque no Ubuntu Noble/24.04 a transição t64 do Debian renomeou
    # libasound2 -> libasound2t64 e libgtk-3-0 -> libgtk-3-0t64. O `grep -q Filename:`
    # diferencia pacote real de virtual stub — `apt-cache show libasound2` no Noble
    # retorna o stub virtual com exit 0, então sem o grep escolheríamos o nome errado.
    pick_pkg() {
        for cand in "$@"; do
            if apt-cache show "$cand" 2>/dev/null | grep -q '^Filename:'; then
                echo "$cand"; return 0
            fi
        done
        return 1
    }

    # Garante que a lista de pacotes apt está atualizada antes de consultar.
    sudo apt update -qq

    LIBASOUND=$(pick_pkg libasound2t64 libasound2) || { err "nem libasound2t64 nem libasound2 disponíveis"; exit 1; }
    LIBGTK3=$(pick_pkg libgtk-3-0t64 libgtk-3-0)   || { err "nem libgtk-3-0t64 nem libgtk-3-0 disponíveis"; exit 1; }

    SYS_PKGS=(
        tor
        curl
        jq
        netcat-openbsd
        python3-pip
        python3-venv
        libdbus-glib-1-2
        libx11-xcb1
        "$LIBASOUND"
        "$LIBGTK3"
    )

else  # macos: lista enxuta — sem libs X11/GTK (Camoufox usa Cocoa via bundled Firefox)
    SYS_PKGS=(
        tor
        curl
        jq
        netcat
        python
    )
fi

MISSING=()
for pkg in "${SYS_PKGS[@]}"; do
    if ! ghost_pkg_is_installed "$pkg"; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Instalando pacotes: ${MISSING[*]}"
    if ghost_pkg_install "${MISSING[@]}"; then
        # Registra o que efetivamente instalamos, para uninstall.sh remover só isso.
        printf '%s\n' "${MISSING[@]}" > "$PKG_TRACK_FILE"
        for p in "${MISSING[@]}"; do INSTALLED+=("pkg: $p"); done
    else
        FAILED+=("pkg: falha ao instalar ${MISSING[*]}")
    fi
else
    info "Todos os pacotes do sistema já estão instalados."
fi
# Marca como SKIPPED os pacotes que já estavam presentes (não em MISSING)
for pkg in "${SYS_PKGS[@]}"; do
    if [[ ${#MISSING[@]} -eq 0 ]] || ! printf '%s\n' "${MISSING[@]}" | grep -qx "$pkg"; then
        SKIPPED+=("pkg: $pkg")
    fi
done

# -------- 1b. browser Chromium-family (skip-if-present) --------
if CHROME_BIN="$(ghost_chrome_binary)" && [[ -n "$CHROME_BIN" ]]; then
    info "Navegador Chromium-based já presente: $CHROME_BIN — pulando instalação."
    SKIPPED+=("chromium-family: $CHROME_BIN já presente")
elif [[ "$OS_KIND" == "macos" ]]; then
    # macOS: instala Chromium via Homebrew Cask. Sem repos de terceiros, sem sudo.
    info "Nenhum browser Chromium-family detectado — instalando 'chromium' via brew cask..."
    if ghost_cask_install chromium; then
        # tracking separado: cask vs formula (uninstall.sh distingue)
        echo "cask:chromium" >> "$PKG_TRACK_FILE"
        INSTALLED+=("cask: chromium (brew)")
    else
        FAILED+=("chromium: 'brew install --cask chromium' falhou")
    fi
elif command -v snap >/dev/null 2>&1; then
    # Linux com snap: chromium-browser é snap transitional
    info "Instalando chromium-browser via apt (snap transitional)..."
    if sudo apt install -y chromium-browser; then
        echo "chromium-browser" >> "$PKG_TRACK_FILE"
        INSTALLED+=("apt: chromium-browser")
    else
        FAILED+=("chromium-browser: apt install falhou")
    fi
else
    # Linux sem snap (Pop!_OS, Debian puro): instala Brave via repositório apt oficial.
    # Brave é Chromium-based, e tem .deb mantido oficialmente — é a opção mais
    # portável fora do mundo snap/flatpak.
    info "Sem snap detectado — instalando Brave via repositório apt oficial..."
    BRAVE_KEY="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
    BRAVE_LIST="/etc/apt/sources.list.d/brave-browser-release.list"
    BRAVE_OK=1
    if [[ ! -f "$BRAVE_KEY" ]]; then
        if ! sudo curl -fsSLo "$BRAVE_KEY" \
                https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg; then
            FAILED+=("brave: falha ao baixar chave GPG do repositório oficial")
            BRAVE_OK=0
        fi
    fi
    if [[ "$BRAVE_OK" -eq 1 && ! -f "$BRAVE_LIST" ]]; then
        echo "deb [signed-by=$BRAVE_KEY] https://brave-browser-apt-release.s3.brave.com/ stable main" \
            | sudo tee "$BRAVE_LIST" >/dev/null
    fi
    if [[ "$BRAVE_OK" -eq 1 ]]; then
        sudo apt update -qq
        if sudo apt install -y brave-browser; then
            echo "brave-browser" >> "$PKG_TRACK_FILE"
            INSTALLED+=("apt: brave-browser (via repo oficial Brave)")
        else
            FAILED+=("brave-browser: apt install falhou após adicionar repo")
        fi
    fi
fi

# -------- 2. serviço Tor --------
# Linux: systemctl enable --now tor. macOS: brew services start tor (persiste
# entre boots automaticamente — não há "enable" separado).
if ghost_service_is_active tor; then
    info "Tor já rodando (SOCKS5 9050 responde)."
    SKIPPED+=("serviço: tor já rodando")
else
    info "Habilitando serviço Tor..."
    if ghost_service_enable tor; then
        INSTALLED+=("serviço: tor habilitado")
    else
        FAILED+=("serviço: falha ao habilitar tor")
    fi
fi

# Confirma que ficou ativo (port 9050 responde após start)
sleep 1
if ! ghost_service_is_active tor; then
    if ghost_service_start tor; then
        sleep 2
    else
        FAILED+=("serviço: falha ao iniciar tor")
    fi
fi

# -------- 3. venv Camoufox --------
if [[ -d "$VENV" ]]; then
    info "venv Camoufox já existe em $VENV — atualizando."
    SKIPPED+=("venv: $VENV já existia")
else
    info "Criando venv Camoufox em $VENV..."
    if python3 -m venv "$VENV"; then
        INSTALLED+=("venv: $VENV criado")
    else
        FAILED+=("venv: falha ao criar $VENV")
        exit 1
    fi
fi

# shellcheck source=/dev/null
source "$VENV/bin/activate"
pip install --upgrade pip
info "Instalando/atualizando camoufox[geoip]..."
if pip install -U "camoufox[geoip]"; then
    INSTALLED+=("pip: camoufox[geoip] instalado/atualizado")
else
    FAILED+=("pip: 'camoufox[geoip]' falhou")
fi

info "Baixando binário Camoufox + dataset GeoIP (pode levar ~3min, ~300MB)..."
if python -m camoufox fetch; then
    INSTALLED+=("camoufox: binário Firefox patched + dataset GeoIP")
else
    FAILED+=("camoufox: 'python -m camoufox fetch' falhou (binário ou GeoIP não baixou)")
fi
deactivate

# -------- 4. validação final --------
# ipinfo.io é bloqueado por Cloudflare quando origem é Tor exit node (retorna body
# vazio com HTTP 200, fazendo o teste antigo falhar mesmo com Tor saudável).
# check.torproject.org é purpose-built para detectar Tor e nunca bloqueia.
info "Testando saída Tor (endpoints Tor-friendly)..."
TOR_OK=0
TOR_RESULT=""
for ep in "https://check.torproject.org/api/ip" "https://api.ipify.org?format=json"; do
    if RESP=$(curl -s --max-time 15 --socks5-hostname 127.0.0.1:9050 "$ep" 2>/dev/null) \
            && [[ -n "$RESP" ]]; then
        TOR_OK=1
        TOR_RESULT="$ep → $RESP"
        break
    fi
done

if [[ "$TOR_OK" -eq 1 ]]; then
    info "Tor OK: $TOR_RESULT"
    INSTALLED+=("tor: saída SOCKS5 confirmada ($TOR_RESULT)")
else
    warn "Não foi possível confirmar Tor em nenhum endpoint testado."
    warn "Pode ser ISP bloqueando, bootstrap incompleto, ou rede caída."
    warn "Diagnóstico: '$(ghost_service_diag_hint tor)'"
    FAILED+=("tor: saída SOCKS5 não confirmada (testou check.torproject.org + ipify)")
fi

# -------- 5. resumo final --------
echo
echo "================ RESUMO DA INSTALAÇÃO ================"
if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    info "Instalado/criado nesta execução (${#INSTALLED[@]}):"
    printf '   [+] %s\n' "${INSTALLED[@]}"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    info "Já presente, pulado (${#SKIPPED[@]}):"
    printf '   [=] %s\n' "${SKIPPED[@]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "Falhou ou requer atenção (${#FAILED[@]}):"
    printf '   [!] %s\n' "${FAILED[@]}"
fi
echo "======================================================"
echo

if [[ ${#FAILED[@]} -eq 0 ]]; then
    info "Instalação concluída sem erros."
else
    warn "Instalação concluída com ${#FAILED[@]} item(ns) de atenção — veja '[!]' acima."
fi
echo
echo "Exemplos:"
echo "  ./ghost.sh                                       # super-comando: pergunta URL, OS aleatório, GPS negado"
echo "  ./ghost.sh https://site.com/signup               # one-liner com URL direta"
echo "  ./spoof-browser.sh windows-chrome                # Caminho A (leve, UA spoof)"
echo "  ./camoufox-spoof.sh macos https://browserleaks.com   # Caminho B manual"
echo "  USE_TOR=0 ./camoufox-spoof.sh linux              # sem Tor"
