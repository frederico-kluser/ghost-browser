#!/usr/bin/env bash
# camoufox-spoof.sh — Caminho B do ghost-browser
# Abre Camoufox (Firefox patched em C++) com OS spoofado de forma coerente
# (navigator.platform, WebGL, fonts, canvas, audio, timezone, fontes…) +
# saída via Tor SOCKS5. Perfil descartável em /tmp.
#
# Uso:
#   ./camoufox-spoof.sh <perfil> [url]
#   USE_TOR=0 ./camoufox-spoof.sh windows   # desliga proxy Tor
#
# Perfis (Camoufox só suporta desktop):
#   windows | macos | linux
#
# Mobile (iPhone/Android) NÃO é suportado por Camoufox. Para esses, use
# ./spoof-browser.sh — mas ciente que será detectado como inconsistente.
#
# Licença: MIT — veja LICENSE

set -euo pipefail

VENV="$HOME/.camoufox-venv"
PROFILE="${1:-windows}"
URL="${2:-https://abrahamjuliot.github.io/creepjs/}"
USE_TOR="${USE_TOR:-1}"

case "$PROFILE" in
  windows|macos|linux) ;;
  *)
    echo "perfis válidos: windows | macos | linux"
    echo "(para iphone/android use ./spoof-browser.sh — porém detectável)"
    exit 1 ;;
esac

if [[ ! -d "$VENV" ]]; then
    echo "[!] venv do Camoufox não encontrado em: $VENV"
    echo "    Rode primeiro: ./install.sh"
    exit 1
fi

TMP="$(mktemp -d -t cfox-XXXXXX)"
echo "[*] Perfil temporário: $TMP"
trap 'echo "[*] Apagando perfil..."; rm -rf "$TMP"' EXIT INT TERM

if [[ "$USE_TOR" == "1" ]]; then
  if ! systemctl is-active --quiet tor; then
    echo "[*] Iniciando serviço tor..."
    sudo systemctl start tor 2>/dev/null || true
    sleep 2
  fi
  echo "[*] Testando saída Tor:"
  curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip || true
  echo
  PROXY_PY='{"server":"socks5://127.0.0.1:9050"}'
else
  PROXY_PY='None'
fi

# shellcheck source=/dev/null
source "$VENV/bin/activate"

python - <<PY
from camoufox.sync_api import Camoufox
from browserforge.fingerprints import Screen

OS_ARG = "$PROFILE"
URL    = "$URL"
UDD    = "$TMP"
PROXY  = $PROXY_PY

screen = None
if OS_ARG == "windows":
    screen = Screen(max_width=1920, max_height=1080)
elif OS_ARG == "macos":
    screen = Screen(max_width=2560, max_height=1600)
elif OS_ARG == "linux":
    screen = Screen(max_width=1920, max_height=1080)

print(f"[*] Abrindo Camoufox como '{OS_ARG}' -> {URL}")

with Camoufox(
    os=OS_ARG,
    headless=False,
    humanize=True,
    geoip=True,                    # casa locale/timezone com IP do Tor
    proxy=PROXY,
    screen=screen,
    user_data_dir=UDD,
    # True => Camoufox chama launch_persistent_context(), que aceita user_data_dir.
    # Em Camoufox 0.4.11 com persistent_context=False, launch() rejeita user_data_dir
    # com TypeError. O perfil ainda é descartável porque o trap do bash apaga $TMP.
    persistent_context=True,
    i_know_what_im_doing=False,
) as browser:
    page = browser.new_page()
    page.goto(URL)
    input("Pressione ENTER para encerrar e apagar o perfil... ")
PY
