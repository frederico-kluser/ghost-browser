# FIXES — histórico de bugs corrigidos

> Documento de histórico. Os 3 bugs originais que motivaram este arquivo já estão
> **todos fechados** no código. Mantido como changelog técnico — útil pra futuras
> investigações se alguma regressão aparecer.
>
> Quer limpar o repo? Pode deletar este arquivo a qualquer momento.

---

## Status atual (12/05/2026)

| # | Bug | Status |
|---|---|---|
| 1 | Teste de Tor no `install.sh` retornando falso negativo via `ipinfo.io` | ✅ FECHADO |
| 2 | `chromium-family não instalado` em Pop!_OS sem snap | ✅ FECHADO |
| 3 | `TypeError: launch() got unexpected kwarg 'user_data_dir'` (Camoufox 0.4.11) | ✅ FECHADO |
| — | Suporte macOS (não bug, evolução) | ✅ ADICIONADO via `lib/platform.sh` |

---

## Bug 1 — `ipinfo.io` como teste de Tor (FALSO POSITIVO)

### Sintoma original
Resumo do `install.sh` reportava `[!] tor: saída SOCKS5 não confirmada` apesar de Tor 100% bootstrapped, porta 9050 em LISTEN e bootstrap log mostrando "Bootstrapped 100% (done)".

### Causa raiz
Cloudflare (na frente do `ipinfo.io`) serve **body vazio com HTTP 200** quando origem é exit node Tor. `curl` retorna `exit=0` mas sem output → `jq -e .` falha em entrada vazia → teste conclui falha mesmo com Tor saudável.

Reproduzido:
```bash
$ curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://ipinfo.io/json
$                                            # (vazio, exit=0)

$ curl -s --max-time 15 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
{"IsTor":true,"IP":"107.189.5.121"}         # (ok)
```

### Fix
`install.sh:229-249` agora tenta endpoints Tor-friendly em cadeia:

1. `https://check.torproject.org/api/ip` — purpose-built pra detectar Tor, nunca bloqueia.
2. `https://api.ipify.org?format=json` — plain JSON, raramente bloqueado.

Considera OK se **qualquer** retornar body não-vazio em até 15s.

### Status
✅ **Fechado**. Confirmado via `curl` direto retornando `{"IsTor":true,"IP":"107.189.5.121"}`.

---

## Bug 2 — `chromium-family: não instalado` (Pop!_OS sem snap)

### Sintoma original
Em Pop!_OS sem `snapd`, nenhum Chromium/Chrome/Brave foi instalado. `./spoof-browser.sh` (Caminho A) não funcionava.

### Causa raiz
- Pop!_OS não vem com `snapd` por design (System76 prefere flatpak).
- Ubuntu Noble removeu `chromium-browser` dos repos apt nativos.
- `install.sh` original só avisava e seguia.

### Fix
`install.sh:115-166` agora:

1. **Já tem Chromium-family?** Pula (`SKIPPED`).
2. **macOS?** Instala `chromium` via `brew install --cask chromium`.
3. **Linux com snap?** `sudo apt install chromium-browser` (snap transitional).
4. **Linux sem snap?** Adiciona repo apt oficial da Brave, instala `brave-browser`.

A rota Brave-via-repo-oficial é a mais portável fora do mundo snap/flatpak e tem `.deb` mantido upstream.

### Status
✅ **Fechado**. `uninstall.sh:92-99` também sabe limpar o repo + chave GPG da Brave se foi instalado por nós.

---

## Bug 3 — `TypeError: launch() got unexpected kwarg 'user_data_dir'` (Camoufox 0.4.11)

### Sintoma original
```
File "camoufox/sync_api.py", line 94, in NewBrowser
    browser = playwright.firefox.launch(**from_options)
TypeError: BrowserType.launch() got an unexpected keyword argument 'user_data_dir'
```

### Causa raiz
Camoufox 0.4.11 escolhe qual método Playwright chamar baseado em `persistent_context`:

| `persistent_context` | Playwright method | aceita `user_data_dir`? |
|---|---|---|
| `False` (default) | `firefox.launch()` | **NÃO** |
| `True` | `firefox.launch_persistent_context()` | SIM |

Tanto `ghost.sh` quanto `camoufox-spoof.sh` passavam `user_data_dir=UDD` com `persistent_context=False` — combinação inválida.

### Fix
Ambos scripts: `persistent_context=True`. Em `ghost.sh`, também trocado `page.wait_for_event("close")` por `browser.wait_for_event("close")` (no contexto), que dispara quando o navegador inteiro encerra.

**Cleanup descartável segue intacto**: o perfil persistente vive em `$TMP` (`/tmp/ghost-XXXXXX` no Linux, `$TMPDIR/ghost-XXXXXX` no macOS), e o `trap cleanup INT TERM HUP EXIT` apaga `$TMP` na saída de qualquer condição.

### Validação
Smoke test headless em Camoufox 0.4.11:
```bash
$ python -c "
from camoufox.sync_api import Camoufox
from browserforge.fingerprints import Screen
import tempfile
tmp = tempfile.mkdtemp()
with Camoufox(os='linux', headless=True, user_data_dir=tmp,
              persistent_context=True,
              firefox_user_prefs={'permissions.default.geo': 2}) as ctx:
    ctx.new_page().goto('about:blank')
    print('OK')
"
OK
```

### Status
✅ **Fechado** em `ghost.sh` e `camoufox-spoof.sh`.

---

## Adição — suporte macOS via `lib/platform.sh`

Não foi um bug, mas vale registrar: depois dos 3 fixes acima, o projeto ganhou suporte macOS através de uma camada de abstração (`lib/platform.sh`) que normaliza diferenças entre Linux e macOS:

- Detecção de S.O. (`ghost_os`)
- Gerenciador de pacotes (`ghost_pkg_*` → `apt` ou `brew`)
- Casks brew (`ghost_cask_*` → só macOS)
- Serviços (`ghost_service_*` → `systemctl` ou `brew services`)
- Caminho do Tor (`ghost_chrome_binary`, `ghost_camoufox_cache_dirs`, `ghost_tor_config_path`, `ghost_tmp_prefix`)

Compatibilidade: bash 3.2 portable (sem `mapfile`, `${var,,}`, ou arrays associativos — `/bin/bash` no macOS é 3.2.57).

Todos os scripts do projeto (`install.sh`, `uninstall.sh`, `ghost.sh`, `camoufox-spoof.sh`, `spoof-browser.sh`, `new-tor-circuit.sh`) agora fazem `source "$SCRIPT_DIR/lib/platform.sh"`.

---

## Como diagnosticar se algo voltar a quebrar

| Item | Comando |
|---|---|
| Tor SOCKS5 | `curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip` |
| Tor bootstrap (Linux) | `journalctl -u tor@default --no-pager \| grep Bootstrap \| tail -5` |
| Tor bootstrap (macOS) | `log show --predicate 'process == "tor"' --last 5m` |
| Tor porta | `nc -z -w 2 127.0.0.1 9050 && echo open \|\| echo closed` |
| Browser detectado | `ghost_chrome_binary` (após `source lib/platform.sh`) |
| Camoufox version | `~/.camoufox-venv/bin/pip show camoufox \| grep Version` |
| Repo Brave (Linux) | `cat /etc/apt/sources.list.d/brave-browser-release.list` |
| Cache Camoufox (macOS) | `ls -la ~/Library/Caches/camoufox/` |
