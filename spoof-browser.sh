#!/usr/bin/env bash
# spoof-browser.sh — Caminho A do ghost-browser
# Abre Chromium isolado com UA falso, perfil descartável e SOCKS5 do Tor.
#
# Uso:
#   ./spoof-browser.sh <perfil> [url] [--no-proxy]
#
# Perfis:
#   windows-chrome | windows-edge | macos-safari | macos-chrome
#   ubuntu-firefox | iphone-safari | galaxy-s24    | ipad-safari
#
# Limitação: este caminho só troca UA + resolução + flags. Plataforma real
# (WebGL renderer, fonts, navigator.platform) continua sendo Linux.
# Para spoofing coerente que passa em CreepJS, use ./camoufox-spoof.sh.
#
# Licença: MIT — veja LICENSE
# Repo:    https://github.com/ondokai/ghost-browser  (placeholder)

set -euo pipefail

PROXY="socks5://127.0.0.1:9050"
URL="${2:-https://browserleaks.com}"
PROFILE="${1:-windows-chrome}"

# Permite "--no-proxy" como terceiro argumento (desliga Tor)
[[ "${3:-}" == "--no-proxy" ]] && PROXY=""

# Detecta binário do Chromium (chromium-browser no Ubuntu, chromium no Debian/Arch)
if   command -v chromium-browser >/dev/null 2>&1; then BROWSER="chromium-browser"
elif command -v chromium         >/dev/null 2>&1; then BROWSER="chromium"
elif command -v google-chrome    >/dev/null 2>&1; then BROWSER="google-chrome"
elif command -v brave-browser    >/dev/null 2>&1; then BROWSER="brave-browser"
else
    echo "[!] Nenhum Chromium/Chrome/Brave encontrado no PATH."
    echo "    Rode primeiro: ./install.sh"
    exit 1
fi

# -------- catálogo de devices --------
case "$PROFILE" in
  windows-chrome)
    UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36'
    WIN="1920,1080" ;;
  windows-edge)
    UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0'
    WIN="1920,1080" ;;
  macos-safari)
    UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15'
    WIN="1440,900" ;;
  macos-chrome)
    UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36'
    WIN="1440,900" ;;
  ubuntu-firefox)
    UA='Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0'
    WIN="1920,1080" ;;
  iphone-safari)
    UA='Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'
    WIN="393,852" ;;
  galaxy-s24)
    UA='Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36'
    WIN="412,915" ;;
  ipad-safari)
    UA='Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
    WIN="1024,1366" ;;
  *)
    echo "Perfil desconhecido: $PROFILE"
    echo "Use um destes: windows-chrome windows-edge macos-safari macos-chrome ubuntu-firefox iphone-safari galaxy-s24 ipad-safari"
    exit 1 ;;
esac

# -------- diretório temporário descartável --------
TMP_PROFILE="$(mktemp -d -t cbrowser-XXXXXXXX)"
echo "[*] Perfil temporário: $TMP_PROFILE"
trap 'echo "[*] Apagando perfil..."; rm -rf "$TMP_PROFILE"' EXIT INT TERM

# -------- garante Tor up se for usar proxy --------
if [[ -n "$PROXY" ]]; then
  if ! systemctl is-active --quiet tor; then
    echo "[*] Iniciando serviço tor..."
    sudo systemctl start tor
    sleep 3
  fi
  echo "[*] Testando saída Tor:"
  curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip || true
  echo
fi

# -------- monta flags do Chromium --------
ARGS=(
  --user-data-dir="$TMP_PROFILE"
  --user-agent="$UA"
  --window-size="$WIN"
  --no-first-run
  --no-default-browser-check
  --disable-features=Translate,InterestFeedContentSuggestions,MediaRouter,AutofillServerCommunication
  --disable-background-networking
  --disable-component-update
  --disable-domain-reliability
  --disable-sync
  --disable-breakpad
  --metrics-recording-only
  --disable-default-apps
  --no-pings
  --password-store=basic
  --use-mock-keychain
  --incognito
)

# Proxy Tor — também força DNS pelo SOCKS para evitar leaks
if [[ -n "$PROXY" ]]; then
  ARGS+=(
    --proxy-server="$PROXY"
    --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"
  )
fi

# UA mobile precisa também avisar o engine que é touch
case "$PROFILE" in
  iphone-safari|galaxy-s24|ipad-safari)
    ARGS+=(--enable-features=TouchEventFeatureDetection --touch-events=enabled)
    ;;
esac

echo "[*] Abrindo $BROWSER como '$PROFILE'..."
exec "$BROWSER" "${ARGS[@]}" "$URL"
