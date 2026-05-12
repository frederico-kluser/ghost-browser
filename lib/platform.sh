#!/usr/bin/env bash
# lib/platform.sh — helpers que abstraem diferenças entre Linux e macOS.
#
# Sourced (não executado) pelos scripts do ghost-browser. Mantém UMA API igual
# em ambos S.O. para os call sites ficarem livres de `if linux/macos`.
#
# Bash 3.2 portable: nada de `mapfile`, `${var,,}`, ou associative arrays —
# /bin/bash no macOS é 3.2.57.
#
# Convenção: helpers retornam 0/1; NUNCA chamam `exit`. Compatível com
# `set -euo pipefail` no chamador — nenhum helper depende de `[[ test ]] && cmd`
# (que falha sob -e quando test é falso).

# ============================================================
# Detecção de S.O.
# ============================================================

# echo "linux" | "macos"; status 1 se outro
ghost_os() {
    if [[ -n "${GHOST_OS:-}" ]]; then
        printf '%s\n' "$GHOST_OS"
        return 0
    fi
    case "$(uname -s)" in
        Linux)  GHOST_OS=linux ;;
        Darwin) GHOST_OS=macos ;;
        *)
            printf 'ghost-browser: S.O. não suportado: %s\n' "$(uname -s)" >&2
            return 1
            ;;
    esac
    export GHOST_OS
    printf '%s\n' "$GHOST_OS"
}

# ============================================================
# Homebrew (macOS)
# ============================================================

# echo brew prefix (ex: /opt/homebrew ou /usr/local); status 1 fora do macOS
ghost_brew_prefix() {
    if [[ -n "${GHOST_BREW_PREFIX:-}" ]]; then
        printf '%s\n' "$GHOST_BREW_PREFIX"
        return 0
    fi
    if ! command -v brew >/dev/null 2>&1; then
        return 1
    fi
    GHOST_BREW_PREFIX="$(brew --prefix)"
    export GHOST_BREW_PREFIX
    printf '%s\n' "$GHOST_BREW_PREFIX"
}

# valida que brew está instalado no macOS; emite instruções se faltar
# status 0 se OK; 1 se ausente
ghost_require_brew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    cat >&2 <<'EOF'
[!] Homebrew não encontrado.
    Instale em https://brew.sh — comando oficial:
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    Depois reabra o terminal e rode novamente este script.
EOF
    return 1
}

# ============================================================
# Pacotes
# ============================================================

# ghost_pkg_is_installed PKG → 0 se instalado, 1 caso contrário
ghost_pkg_is_installed() {
    local pkg="$1"
    case "$(ghost_os)" in
        linux)
            dpkg -s "$pkg" >/dev/null 2>&1
            ;;
        macos)
            brew list --formula --versions "$pkg" >/dev/null 2>&1
            ;;
    esac
}

# ghost_pkg_install PKG [PKG...] — instala formulae (sem sudo no macOS)
ghost_pkg_install() {
    case "$(ghost_os)" in
        linux)
            sudo apt install -y "$@"
            ;;
        macos)
            brew install "$@"
            ;;
    esac
}

# ghost_pkg_remove PKG [PKG...]
ghost_pkg_remove() {
    case "$(ghost_os)" in
        linux)
            sudo apt remove -y "$@" && sudo apt autoremove -y
            ;;
        macos)
            brew uninstall "$@"
            ;;
    esac
}

# ghost_cask_is_installed CASK → apenas macOS; status 1 no Linux
ghost_cask_is_installed() {
    case "$(ghost_os)" in
        macos) brew list --cask --versions "$1" >/dev/null 2>&1 ;;
        *)     return 1 ;;
    esac
}

ghost_cask_install() {
    case "$(ghost_os)" in
        macos) brew install --cask "$@" ;;
        *)     return 1 ;;
    esac
}

ghost_cask_uninstall() {
    case "$(ghost_os)" in
        macos) brew uninstall --cask "$@" ;;
        *)     return 1 ;;
    esac
}

# ============================================================
# Serviços (Tor é o único atualmente)
# ============================================================

# ghost_port_open HOST PORT → 0 se TCP responde, 1 se não. Timeout 2s.
# nc -z funciona em Linux netcat-openbsd e macOS BSD nc.
ghost_port_open() {
    nc -z -w 2 "$1" "$2" >/dev/null 2>&1
}

# ghost_service_is_active NAME → 0 se rodando
# Para "tor", usa port check em 9050 (funciona pra qualquer método de install).
# Outros nomes: dispatch ao init system.
ghost_service_is_active() {
    local name="$1"
    if [[ "$name" == "tor" ]]; then
        ghost_port_open 127.0.0.1 9050
        return $?
    fi
    case "$(ghost_os)" in
        linux) systemctl is-active --quiet "$name" ;;
        macos) brew services list 2>/dev/null \
                 | awk -v n="$name" '$1==n && $2=="started"{found=1} END{exit !found}' ;;
    esac
}

ghost_service_start() {
    case "$(ghost_os)" in
        linux) sudo systemctl start "$1" ;;
        macos) brew services start "$1" ;;
    esac
}

# No macOS, `brew services start` já persiste no boot — enable == start.
ghost_service_enable() {
    case "$(ghost_os)" in
        linux) sudo systemctl enable --now "$1" ;;
        macos) brew services start "$1" ;;
    esac
}

ghost_service_reload() {
    case "$(ghost_os)" in
        linux) sudo systemctl reload "$1" ;;
        macos) brew services restart "$1" ;;
    esac
}

ghost_service_disable() {
    case "$(ghost_os)" in
        linux) sudo systemctl disable --now "$1" 2>/dev/null || true ;;
        macos) brew services stop "$1" 2>/dev/null || true ;;
    esac
}

# Hint de diagnóstico para o usuário rodar manualmente. Sem newline final.
ghost_service_diag_hint() {
    local name="$1"
    case "$(ghost_os)" in
        linux) printf 'journalctl -u %s@default | grep Bootstrap | tail -5' "$name" ;;
        macos) printf 'brew services info %s --json | jq . ; log show --predicate '\''process == "%s"'\'' --last 5m' "$name" "$name" ;;
    esac
}

# ============================================================
# Caminhos / binários
# ============================================================

# Echo do primeiro binário Chromium-family encontrado. Caminho absoluto.
# Caller deve usar com aspas: "$BROWSER".
ghost_chrome_binary() {
    case "$(ghost_os)" in
        linux)
            local b
            for b in chromium-browser chromium google-chrome brave-browser; do
                if command -v "$b" >/dev/null 2>&1; then
                    command -v "$b"
                    return 0
                fi
            done
            ;;
        macos)
            # /Applications/ paths — ordem reflete preferência (Chromium puro > Brave > Chrome > Edge)
            local app
            for app in \
                "/Applications/Chromium.app/Contents/MacOS/Chromium" \
                "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
                "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
                "$HOME/Applications/Chromium.app/Contents/MacOS/Chromium" \
                "$HOME/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
                "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            do
                if [[ -x "$app" ]]; then
                    printf '%s\n' "$app"
                    return 0
                fi
            done
            ;;
    esac
    return 1
}

# Diretórios candidatos do cache binário do Camoufox (1 por linha).
# Removemos todos no uninstall — Camoufox usa platformdirs e pode escolher
# qualquer um dependendo da versão.
ghost_camoufox_cache_dirs() {
    case "$(ghost_os)" in
        linux)
            printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/camoufox"
            printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/camoufox"
            ;;
        macos)
            printf '%s\n' "$HOME/Library/Caches/camoufox"
            printf '%s\n' "$HOME/Library/Application Support/camoufox"
            ;;
    esac
}

# Caminho do torrc principal
ghost_tor_config_path() {
    case "$(ghost_os)" in
        linux) printf '/etc/tor/torrc\n' ;;
        macos)
            local prefix
            prefix="$(ghost_brew_prefix)" || prefix="/opt/homebrew"
            printf '%s/etc/tor/torrc\n' "$prefix"
            ;;
    esac
}

# Prefix de diretório temporário (usado em globs de cleanup)
ghost_tmp_prefix() {
    printf '%s\n' "${TMPDIR:-/tmp}"
}
