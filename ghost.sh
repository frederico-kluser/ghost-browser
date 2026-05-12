#!/usr/bin/env bash
# ghost.sh — super-comando do ghost-browser
#
# Pergunta a URL de cadastro, força novo circuito Tor, abre Camoufox com OS
# spoofado aleatório (windows|macos|linux), nega geolocalização silenciosamente
# e apaga tudo (perfil temporário + browser) quando o usuário:
#   - fechar a janela do navegador
#   - apertar Ctrl+C no terminal
#   - fechar a janela do terminal
#
# Uso:
#   ./ghost.sh                       # pergunta a URL
#   ./ghost.sh https://site/signup   # passa URL direto
#
# Licença: MIT — veja LICENSE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

VENV="$HOME/.camoufox-venv"

# -------- cleanup robusto: INT, TERM, HUP, EXIT --------
TMP=""
cleanup() {
    local rc=$?
    [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"
    exit $rc
}
trap cleanup INT TERM HUP EXIT

# -------- pré-checks --------
OS_KIND="$(ghost_os)" || { echo "[!] S.O. não suportado"; exit 1; }

if [[ ! -d "$VENV" ]]; then
    echo "[!] venv Camoufox não encontrado em $VENV"
    echo "    Rode primeiro: ./install.sh"
    exit 1
fi

if [[ ! -x "$SCRIPT_DIR/new-tor-circuit.sh" ]]; then
    echo "[!] new-tor-circuit.sh não encontrado/executável em $SCRIPT_DIR"
    exit 1
fi

# Garante Tor rodando antes de pedir circuito novo — evita "desconhecido" no IP.
if ! ghost_service_is_active tor; then
    echo "[ghost] iniciando Tor ($OS_KIND)..."
    ghost_service_start tor 2>/dev/null || true
    sleep 3
fi

# -------- pede URL (aceita também via $1) --------
URL="${1:-}"
if [[ -z "$URL" ]]; then
    read -r -p "[ghost] URL de cadastro: " URL
fi
if [[ -z "$URL" ]]; then
    echo "[!] URL vazia, abortando."
    exit 1
fi
# se faltou esquema, prepende https://
if [[ ! "$URL" =~ ^https?:// ]]; then
    URL="https://$URL"
fi

# -------- OS aleatório a cada run --------
OS_LIST=(windows macos linux)
OS_RAND="${OS_LIST[$((RANDOM % ${#OS_LIST[@]}))]}"

# -------- novo circuito Tor --------
echo "[ghost] forçando novo circuito Tor..."
"$SCRIPT_DIR/new-tor-circuit.sh" || true

# -------- perfil descartável --------
# Usa $TMPDIR no macOS (/var/folders/.../T); cai pra /tmp no Linux. mktemp aceita.
TMP="$(mktemp -d "$(ghost_tmp_prefix)/ghost-XXXXXX")"
echo "[ghost] OS spoof : $OS_RAND"
echo "[ghost] perfil   : $TMP"
echo "[ghost] URL      : $URL"

# -------- dispara Camoufox --------
# shellcheck source=/dev/null
source "$VENV/bin/activate"

python - <<PY
import signal, sys
from camoufox.sync_api import Camoufox
from browserforge.fingerprints import Screen

# encerra limpo em SIGHUP/SIGTERM (SIGINT já vira KeyboardInterrupt)
for s in (signal.SIGHUP, signal.SIGTERM):
    signal.signal(s, lambda *_: sys.exit(0))

URL    = "$URL"
OS_ARG = "$OS_RAND"
UDD    = "$TMP"

screens = {
    "windows": Screen(max_width=1920, max_height=1080),
    "macos":   Screen(max_width=2560, max_height=1600),
    "linux":   Screen(max_width=1920, max_height=1080),
}

print(f"[ghost] abrindo Camoufox como '{OS_ARG}' -> {URL}")

with Camoufox(
    os=OS_ARG,
    headless=False,
    humanize=True,
    geoip=True,
    proxy={"server": "socks5://127.0.0.1:9050"},
    screen=screens[OS_ARG],
    user_data_dir=UDD,
    # True => Camoufox usa launch_persistent_context() (aceita user_data_dir).
    # Sem isso, Playwright reclama: "launch() got unexpected kwarg user_data_dir".
    # Cleanup permanece: bash trap apaga $TMP de qualquer forma.
    persistent_context=True,
    # 0=prompt, 1=allow, 2=deny — nega GPS sem mostrar prompt no site
    firefox_user_prefs={"permissions.default.geo": 2},
) as browser:
    # persistent_context=True devolve BrowserContext (não Browser).
    # BrowserContext.new_page() existe normalmente em Playwright.
    page = browser.new_page()
    page.goto(URL)
    try:
        # bloqueia até o usuário fechar o navegador inteiro (todas as janelas).
        # Context emite "close" quando o processo Firefox encerra.
        browser.wait_for_event("close", timeout=0)
    except (KeyboardInterrupt, SystemExit):
        pass
PY
