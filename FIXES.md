# FIXES — correções pendentes (temporário)

> Documento temporário com os 2 problemas detectados na instalação atual,
> a análise de causa raiz, o que já foi corrigido no `install.sh` e o que
> ainda precisa de ação manual. Deletar quando ambos estiverem `[+]` no
> resumo do `install.sh`.

---

## Resumo da instalação atual

```
================ RESUMO DA INSTALAÇÃO ================
[+] venv: /home/ondokai/.camoufox-venv criado
[+] pip: camoufox[geoip] instalado/atualizado
[+] camoufox: binário Firefox patched + dataset GeoIP
[=] apt: tor / curl / jq / netcat-openbsd / python3-pip / python3-venv
[=] apt: libdbus-glib-1-2 / libx11-xcb1 / libasound2t64 / libgtk-3-0t64
[=] serviço: tor já habilitado
[!] chromium-family: não instalado (sem snap)
[!] tor: saída SOCKS5 não confirmada
======================================================
```

Diagnóstico: **um falso positivo + uma instalação faltando**.

---

## Bug 1 — `tor: saída SOCKS5 não confirmada` (FALSO POSITIVO)

### Sintoma
Resumo marca Tor como falha apesar de `systemctl is-active tor@default` retornar `active`, porta `9050` em `LISTEN` e bootstrap em `100% (done)`.

### Causa raiz
O teste antigo em `install.sh` usava `https://ipinfo.io/json`. **Cloudflare (na frente do ipinfo.io) serve body vazio com HTTP 200 quando a origem é exit node Tor.** Resultado: `curl` retorna `exit=0` mas body vazio → `jq -e .` falha em entrada vazia → resumo conclui falha mesmo com Tor 100% saudável.

Reproduzido localmente:
```bash
$ curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://ipinfo.io/json
$                                           # (vazio, exit=0)

$ curl -s --max-time 15 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
{"IsTor":true,"IP":"107.189.5.121"}        # (ok)
```

### Fix aplicado em `install.sh`
Substituí o teste por uma tentativa em cadeia com endpoints Tor-friendly:

1. `https://check.torproject.org/api/ip` — purpose-built para detecção Tor, nunca bloqueia
2. `https://api.ipify.org?format=json` — plain-text/JSON IP, raramente bloqueado

Considera OK se **qualquer** retornar body não-vazio em até 15s.

```bash
# install.sh — bloco já editado
for ep in "https://check.torproject.org/api/ip" "https://api.ipify.org?format=json"; do
    if RESP=$(curl -s --max-time 15 --socks5-hostname 127.0.0.1:9050 "$ep" 2>/dev/null) \
            && [[ -n "$RESP" ]]; then
        TOR_OK=1; TOR_RESULT="$ep → $RESP"; break
    fi
done
```

### Status
✅ **Corrigido**. Rodando `./install.sh` de novo, este item vai pra `[+]`.

---

## Bug 2 — `chromium-family: não instalado` (INSTALAÇÃO FALTANDO)

### Sintoma
Em Pop!_OS sem `snapd`, nenhum Chromium/Chrome/Brave foi instalado. `./spoof-browser.sh` (Caminho A) não funciona.

### Causa raiz
- Pop!_OS não vem com `snapd` por design (System76 prefere flatpak).
- Ubuntu Noble removeu `chromium-browser` dos repositórios apt nativos (transitional para snap).
- `install.sh` antigo só avisava e seguia.

### Fix aplicado em `install.sh`
Quando snap está ausente, agora **instala Brave automaticamente** via repositório apt oficial (Brave é Chromium-based, já detectado por `spoof-browser.sh:32`, tem `.deb` mantido oficialmente):

```bash
# install.sh — bloco já editado (resumo)
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update -qq
sudo apt install -y brave-browser
```

### Status
⏳ **Pendente ação do usuário**. O classificador automático do Claude Code bloqueia adição de repo apt de terceiros sem autorização explícita. Três caminhos:

#### Opção A — Re-rodar `./install.sh` (mais simples)
```bash
./install.sh
```
Ele detecta ausência de snap, baixa chave, adiciona repo, instala Brave. Vai pedir sudo uma vez.

#### Opção B — Snippet manual (se quiser entender cada passo)
```bash
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
  https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg && \
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
  sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null && \
sudo apt update -qq && sudo apt install -y brave-browser
```

#### Opção C — Flatpak (sem repo apt system-wide)
Pop!_OS já tem flatpak instalado. Custo: `spoof-browser.sh:29-37` não detecta apps flatpak (chama `brave-browser` por nome de binário, não `flatpak run com.brave.Browser`), então precisaria de patch.

```bash
flatpak install --user -y flathub com.brave.Browser
# + patch em spoof-browser.sh (não recomendado)
```

#### Opção D — Pular (se só usa `./ghost.sh`)
Se sua meta é só cadastrar contas (caso de uso original), **Caminho A é irrelevante**:
- `./ghost.sh` usa Camoufox (Caminho B), fingerprint coerente, Trust >70% em CreepJS.
- Caminho A só serve pra perfis mobile (iPhone/Android UA), que são detectados como inconsistentes de qualquer jeito.
- Decisão honesta: **deletar este FIXES.md e seguir com ghost.sh**.

---

## Como reavaliar depois

Rodando `./install.sh` (ou aplicando Opção B), o resumo final esperado:

```
[+] tor: saída SOCKS5 confirmada (https://check.torproject.org/api/ip → {"IsTor":true,...})
[+] apt: brave-browser (via repo oficial Brave)
```

Ambos os `[!]` viram `[+]`. Aí pode `rm FIXES.md`.

Se mesmo após o re-run algum item continuar em `[!]`, diagnósticos rápidos:

| Item | Comando de diagnóstico |
|---|---|
| Tor SOCKS5 | `curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip` |
| Tor bootstrap | `journalctl -u tor@default --no-pager \| grep Bootstrap \| tail -5` |
| Tor porta | `ss -tlnp \| grep 9050` |
| Brave | `command -v brave-browser && brave-browser --version` |
| Repo Brave ativo | `cat /etc/apt/sources.list.d/brave-browser-release.list` |

---

## Bug 3 — `TypeError: launch() got unexpected kwarg 'user_data_dir'` (RUNTIME)

### Sintoma
Ao rodar `./ghost.sh`, depois de pegar IP Tor novo e tentar abrir Camoufox:

```
File "camoufox/sync_api.py", line 94, in NewBrowser
    browser = playwright.firefox.launch(**from_options)
TypeError: BrowserType.launch() got an unexpected keyword argument 'user_data_dir'
```

### Causa raiz
Camoufox 0.4.11 escolhe qual método Playwright chamar baseado em `persistent_context`:

| `persistent_context` | método Playwright | aceita `user_data_dir`? |
|---|---|---|
| `False` (default) | `firefox.launch(**from_options)` | **NÃO** |
| `True` | `firefox.launch_persistent_context(**from_options)` | SIM |

Tanto `ghost.sh` quanto o `camoufox-spoof.sh` original passavam `user_data_dir=UDD` **junto** com `persistent_context=False`. Camoufox encaminha todos os kwargs sem filtrar, e o Playwright rejeita o arg incompatível.

Verificado lendo `~/.camoufox-venv/lib/python3.12/site-packages/camoufox/sync_api.py:85-93`:

```python
# Persistent context
if persistent_context:
    context = playwright.firefox.launch_persistent_context(**from_options)
    return sync_attach_vd(context, virtual_display)

# Browser
browser = playwright.firefox.launch(**from_options)
return sync_attach_vd(browser, virtual_display)
```

### Fix aplicado
Em ambos `ghost.sh` e `camoufox-spoof.sh`:

```python
with Camoufox(
    ...
    user_data_dir=UDD,
    persistent_context=True,   # <- era False
    ...
) as browser:
    # browser agora é BrowserContext (não Browser). BrowserContext.new_page() funciona igual.
    page = browser.new_page()
```

Em `ghost.sh`, também substituí `page.wait_for_event("close")` por `browser.wait_for_event("close")` (no contexto), que dispara quando o navegador inteiro fecha — não só uma aba.

**Cleanup descartável continua intacto**: o perfil persistente fica em `$TMP` (`/tmp/ghost-XXXXXX`), e o `trap cleanup INT TERM HUP EXIT` do bash apaga `$TMP` de qualquer forma. "Persistent" no nome do método é só sobre Playwright manter estado entre páginas dentro do **mesmo run**, não entre runs.

### Validação
Smoke test headless em Camoufox 0.4.11:

```bash
$ python -c "
from camoufox.sync_api import Camoufox
from browserforge.fingerprints import Screen
import tempfile, pathlib
tmp = tempfile.mkdtemp()
with Camoufox(os='linux', headless=True, user_data_dir=tmp,
              persistent_context=True,
              firefox_user_prefs={'permissions.default.geo': 2}) as ctx:
    page = ctx.new_page()
    page.goto('about:blank')
    print('OK', page.title())
"
OK
```

### Status
✅ **Corrigido em ghost.sh e camoufox-spoof.sh**. Rodar `./ghost.sh` agora deve abrir o navegador normalmente.

---

## Arquivos tocados pelos fixes

- `install.sh` — 2 blocos editados (teste Tor + fallback Chromium-family).
- `ghost.sh` — `persistent_context=True` + `browser.wait_for_event` em vez de `page.wait_for_event`.
- `camoufox-spoof.sh` — `persistent_context=True`.
- `spoof-browser.sh`, `new-tor-circuit.sh`, `uninstall.sh` — não afetados.
