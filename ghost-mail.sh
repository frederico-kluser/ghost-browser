#!/usr/bin/env bash
# ghost-mail.sh — e-mail descartável aleatório com leitura em tempo real
#
# Cria (ou recarrega) uma conta de e-mail temporária no mail.tm — serviço
# gratuito, sem API key e sem cadastro — imprime o endereço e fica observando
# a caixa de entrada, mostrando cada mensagem nova no MESMO terminal em tempo
# real (polling). Casa com a filosofia do ghost-browser: identidade efêmera
# (perfil descartável => conta apagada ao sair).
#
# Roda sozinho OU é disparado por `MAIL=1 ./ghost.sh <url>` (que reaproveita
# o mesmo proxy/Tor e o mesmo diretório de perfil do navegador).
#
# Uso:
#   ./ghost-mail.sh                         # endereço efêmero (apaga ao sair)
#   KEEP=trabalho ./ghost-mail.sh           # endereço persistente (mesmo padrão de ghost.sh)
#   ./ghost-mail.sh /caminho/do/perfil      # guarda credenciais nesse diretório
#
# Env vars (todas opcionais):
#   PROXY            tor (default) | none | socks5://h:p | http://h:p | https://h:p
#                    (mesmo formato de ghost.sh — chamadas ao mail.tm passam por aqui)
#   GHOST_MAIL_PROXY override só pro e-mail (ex.: GHOST_MAIL_PROXY=none se o
#                    exit node Tor estiver bloqueado pelo Cloudflare do mail.tm)
#   GHOST_MAIL_POLL  intervalo de polling em segundos (default 5; mínimo 2)
#   KEEP             nome do perfil persistente (~/.ghost-browser/profiles/<nome>/)
#
# Inbox by mail.tm (https://mail.tm) — atribuição exigida pelos termos do serviço.
#
# Licença: MIT — veja LICENSE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

API="https://api.mail.tm"

case "${1:-}" in
    -h|--help)
        sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

# -------- pré-checks --------
for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        err "'$bin' não encontrado. Rode primeiro: ./install.sh"
        exit 1
    fi
done

# -------- resolve perfil (onde guardar credenciais) + efemeridade --------
# Precedência: GHOST_MAIL_PROFILE (vindo de ghost.sh) > $1 > KEEP > tmp.
PROFILE_DIR=""
PERSISTENT=0
OWNS_TMPDIR=0

if [[ -n "${GHOST_MAIL_PROFILE:-}" ]]; then
    PROFILE_DIR="$GHOST_MAIL_PROFILE"
    PERSISTENT="${GHOST_MAIL_PERSISTENT:-0}"
elif [[ -n "${1:-}" ]]; then
    PROFILE_DIR="$1"
    PERSISTENT=1
elif [[ -n "${KEEP:-}" ]]; then
    if [[ ! "$KEEP" =~ ^[A-Za-z0-9_-]+$ ]]; then
        err "KEEP inválido: '$KEEP' (use só letras, números, '_' e '-')"
        exit 1
    fi
    PROFILE_DIR="$HOME/.ghost-browser/profiles/$KEEP"
    PERSISTENT=1
else
    PROFILE_DIR="$(mktemp -d "$(ghost_tmp_prefix)/ghost-mail-XXXXXX")"
    PERSISTENT=0
    OWNS_TMPDIR=1
fi
mkdir -p "$PROFILE_DIR"
CRED_FILE="$PROFILE_DIR/.ghost-mail"

# -------- resolve proxy (mesmo case de ghost.sh) --------
resolve_proxy_url() {
    case "${1:-}" in
        ""|tor)                   printf 'socks5://127.0.0.1:9050\n' ;;
        none)                     printf '\n' ;;
        socks5://*|http://*|https://*) printf '%s\n' "$1" ;;
        *)                        return 1 ;;
    esac
}

if [[ -n "${GHOST_MAIL_PROXY:-}" ]]; then
    PROXY_SRC="GHOST_MAIL_PROXY"
    PROXY_URL="$(resolve_proxy_url "$GHOST_MAIL_PROXY")" \
        || { err "GHOST_MAIL_PROXY inválido: '$GHOST_MAIL_PROXY'"; exit 1; }
elif [[ "${GHOST_PROXY_RESOLVED:-0}" == "1" ]]; then
    PROXY_SRC="ghost.sh"
    PROXY_URL="${GHOST_PROXY_URL:-}"
else
    PROXY_SRC="PROXY"
    PROXY_URL="$(resolve_proxy_url "${PROXY:-}")" \
        || { err "PROXY inválido: '${PROXY:-}'"; exit 1; }
fi

CURL_PROXY_ARGS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && CURL_PROXY_ARGS+=("$line")
done < <(ghost_curl_proxy_args "$PROXY_URL" || true)
PROXY_LABEL="${PROXY_URL:-direto (sem proxy)}"

# -------- HTTP helper: popula RESP_BODY / RESP_CODE --------
TOKEN=""
RESP_BODY=""
RESP_CODE="000"
mt_request() {
    local method="$1" path="$2" body="${3:-}"
    local args=( -sS --max-time "${MAIL_HTTP_TIMEOUT:-20}" -X "$method"
                 -H 'Accept: application/json' )
    if [[ -n "$body" ]]; then
        args+=( -H 'Content-Type: application/json' --data "$body" )
    fi
    if [[ -n "$TOKEN" ]]; then
        args+=( -H "Authorization: Bearer $TOKEN" )
    fi
    local raw
    raw="$(curl "${args[@]}" \
        ${CURL_PROXY_ARGS[@]+"${CURL_PROXY_ARGS[@]}"} \
        -w $'\n%{http_code}' "$API$path" 2>/dev/null || true)"
    RESP_CODE="${raw##*$'\n'}"
    RESP_BODY="${raw%$'\n'*}"
    [[ "$RESP_CODE" =~ ^[0-9]{3}$ ]] || { RESP_CODE="000"; RESP_BODY=""; }
}

# jq sobre RESP_BODY, à prova de corpo não-JSON (ex.: página do Cloudflare)
jqr() { jq -r "$1" <<<"$RESP_BODY" 2>/dev/null || true; }
# Normaliza coleção (array puro com Accept:json, ou envelope Hydra antigo)
collection() {
    jq -c 'if type=="object" and has("hydra:member") then ."hydra:member" else . end' \
        <<<"$RESP_BODY" 2>/dev/null || echo '[]'
}

rand_str() {
    local n="${1:-12}"
    LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c "$n" || true
}

# -------- credenciais --------
ADDRESS=""
PASSWORD=""
ACCOUNT_ID=""

save_creds() {
    ( umask 077
      jq -nc \
        --arg address "$ADDRESS" --arg password "$PASSWORD" \
        --arg accountId "$ACCOUNT_ID" --arg token "$TOKEN" \
        '{address:$address,password:$password,accountId:$accountId,token:$token}' \
        > "$CRED_FILE" )
}

load_creds() {
    [[ -s "$CRED_FILE" ]] || return 1
    ADDRESS="$(jq -r '.address // empty' "$CRED_FILE" 2>/dev/null || true)"
    PASSWORD="$(jq -r '.password // empty' "$CRED_FILE" 2>/dev/null || true)"
    ACCOUNT_ID="$(jq -r '.accountId // empty' "$CRED_FILE" 2>/dev/null || true)"
    TOKEN="$(jq -r '.token // empty' "$CRED_FILE" 2>/dev/null || true)"
    [[ -n "$ADDRESS" && -n "$PASSWORD" ]]
}

# POST /token com ADDRESS/PASSWORD atuais. 0 = token renovado.
get_token() {
    local body
    body="$(jq -nc --arg a "$ADDRESS" --arg p "$PASSWORD" \
        '{address:$a,password:$p}')"
    TOKEN=""
    mt_request POST /token "$body"
    [[ "$RESP_CODE" == "200" ]] || return 1
    TOKEN="$(jqr '.token // empty')"
    local id; id="$(jqr '.id // empty')"
    [[ -n "$id" ]] && ACCOUNT_ID="$id"
    [[ -n "$TOKEN" ]]
}

provision_failed() {
    err "Não consegui criar a caixa no mail.tm (HTTP ${RESP_CODE})."
    if [[ -n "$PROXY_URL" ]]; then
        warn "Provável bloqueio/Cloudflare no exit node ($PROXY_LABEL via $PROXY_SRC)."
        warn "Tente trocar de circuito:  ./new-tor-circuit.sh"
        warn "Ou mande só o e-mail direto: GHOST_MAIL_PROXY=none $0"
        warn "(no fluxo integrado:  MAIL=1 GHOST_MAIL_PROXY=none ./ghost.sh <url>)"
    else
        warn "Sem conexão com api.mail.tm? Confira a rede e tente de novo."
    fi
}

# Cria conta nova (domínio -> /accounts -> /token) e grava credenciais.
provision_fresh() {
    mt_request GET /domains
    if [[ "$RESP_CODE" != "200" ]]; then provision_failed; return 1; fi
    local domain
    domain="$(collection | jq -r \
        'first(.[] | select(.isActive!=false) | .domain) // empty' 2>/dev/null || true)"
    if [[ -z "$domain" ]]; then
        err "mail.tm não devolveu nenhum domínio ativo."; return 1
    fi

    local body
    for _ in 1 2 3 4 5; do
        ADDRESS="ghost$(rand_str 12)@$domain"
        PASSWORD="$(rand_str 24)"
        body="$(jq -nc --arg a "$ADDRESS" --arg p "$PASSWORD" \
            '{address:$a,password:$p}')"
        mt_request POST /accounts "$body"
        case "$RESP_CODE" in
            201) ACCOUNT_ID="$(jqr '.id // empty')"; break ;;
            422) continue ;;                      # endereço colidiu, tenta outro
            *)   provision_failed; return 1 ;;
        esac
    done
    [[ -n "$ACCOUNT_ID" ]] || { provision_failed; return 1; }

    if ! get_token; then provision_failed; return 1; fi
    save_creds
}

banner() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}e-mail descartável (tempo real)${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}${GREEN}$ADDRESS${NC}"
    echo -e "${CYAN}║${NC} perfil : $PROFILE_DIR$( [[ "$PERSISTENT" == "1" ]] && printf ' (persistente)' || printf ' (efêmero — apaga ao sair)' )"
    echo -e "${CYAN}║${NC} rede   : $PROXY_LABEL"
    echo -e "${CYAN}║${NC} inbox by mail.tm — https://mail.tm"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    info "observando a caixa (Ctrl+C encerra)..."
}

# -------- cleanup: apaga conta se efêmero --------
CLEANED=0
SLEEP_PID=""
cleanup() {
    local rc=$?
    if [[ "$CLEANED" -eq 1 ]]; then exit "$rc"; fi
    CLEANED=1
    # Interrompe o nap pendente pra encerrar na hora (ghost.sh dá kill+wait).
    if [[ -n "$SLEEP_PID" ]]; then
        kill "$SLEEP_PID" 2>/dev/null || true
    fi
    if [[ "$PERSISTENT" -eq 0 && -n "$ACCOUNT_ID" && -n "$TOKEN" ]]; then
        MAIL_HTTP_TIMEOUT=8 mt_request DELETE "/accounts/$ACCOUNT_ID" || true
    fi
    if [[ "$OWNS_TMPDIR" -eq 1 && -d "$PROFILE_DIR" ]]; then
        rm -rf "$PROFILE_DIR"
    fi
    exit "$rc"
}
trap cleanup INT TERM HUP EXIT

# -------- provisiona ou recarrega --------
if [[ "$PERSISTENT" -eq 1 ]] && load_creds; then
    if get_token; then
        save_creds
        info "reutilizando endereço persistente."
    else
        warn "conta persistente expirou no mail.tm — criando outra."
        provision_fresh || exit 1
    fi
else
    provision_fresh || exit 1
fi

banner

# -------- loop de polling em tempo real --------
POLL="${GHOST_MAIL_POLL:-5}"
[[ "$POLL" =~ ^[0-9]+$ && "$POLL" -ge 2 ]] || POLL=5
SEEN=$'\n'

# Sleep interrompível: roda em background e dá `wait` — assim um sinal
# (INT/TERM/HUP) dispara o trap NA HORA, sem esperar o sleep terminar.
# Sem isso, fechar o navegador faria o ghost.sh travar até POLL segundos.
nap() {
    sleep "$1" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null || true
    SLEEP_PID=""
}

print_message() {
    local id="$1"
    mt_request GET "/messages/$id"
    [[ "$RESP_CODE" == "200" ]] || return 0

    local from subj date body code
    from="$(jqr '((.from.name // "") + " <" + (.from.address // "?") + ">") | ltrimstr(" ")')"
    subj="$(jqr '.subject // "(sem assunto)"')"
    date="$(jqr '.createdAt // ""')"
    body="$(jqr '.text // ""')"
    if [[ -z "${body// /}" ]]; then
        body="$(jqr '(.html // []) | join("\n")' \
            | sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g')"
    fi
    code="$(printf '%s' "$body $subj" \
        | grep -Eo '[0-9]{4,8}' | head -n1 || true)"

    echo
    echo -e "${CYAN}── ✉  novo e-mail · $(date '+%H:%M:%S') ──────────────────────────${NC}"
    echo -e "${BOLD}De     :${NC} $from"
    echo -e "${BOLD}Assunto:${NC} $subj"
    echo -e "${BOLD}Data   :${NC} $date"
    [[ -n "$code" ]] && echo -e "${BOLD}${GREEN}Código provável:${NC} ${BOLD}$code${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    printf '%s\n' "$body" | sed -e 's/\r$//' | head -n 60 || true
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

while true; do
    mt_request GET /messages
    if [[ "$RESP_CODE" == "401" ]]; then
        if ! get_token; then
            warn "sessão mail.tm caiu e não renovou — encerrando watcher."
            exit 1
        fi
        save_creds
        continue
    fi
    if [[ "$RESP_CODE" == "200" ]]; then
        # mail.tm lista do mais novo pro mais antigo; imprime em ordem cronológica.
        NEW_IDS=""
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            case "$SEEN" in
                *$'\n'"$id"$'\n'*) ;;                 # já visto
                *) NEW_IDS="$id"$'\n'"$NEW_IDS"; SEEN="$SEEN$id"$'\n' ;;
            esac
        done < <(collection | jq -r '.[].id' 2>/dev/null || true)
        while IFS= read -r id; do
            [[ -n "$id" ]] && print_message "$id"
        done <<< "$NEW_IDS"
    elif [[ "$RESP_CODE" == "429" ]]; then
        warn "rate limit do mail.tm (429) — aguardando mais um pouco."
        nap 5
    elif [[ "$RESP_CODE" != "200" ]]; then
        : # 000/5xx: rede instável ou exit Tor lento — segue tentando em silêncio
    fi
    nap "$POLL"
done
