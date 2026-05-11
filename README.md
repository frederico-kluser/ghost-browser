# ghost-browser

> Navegador Linux **isolado, descartável e com IP + fingerprint trocados**, via scripts `.sh`.

Dois caminhos lado a lado: um leve (Chromium + UA spoof) e um sério (Camoufox, que troca `navigator`, `screen`, `WebGL`, `canvas`, `audio`, fontes, `timezone` e geolocalização de forma coerente em nível C++).

---

## TL;DR

```bash
./install.sh                              # instala Tor + Chromium + Camoufox
./spoof-browser.sh windows-chrome         # Caminho A — leve, falso de Windows via Tor
./camoufox-spoof.sh macos                 # Caminho B — fingerprint coerente de macOS via Tor
```

---

## Instalação

Requer Ubuntu/Debian 22.04+, com `sudo`.

```bash
./install.sh
```

Isso instala (idempotentemente):

- `tor` (proxy SOCKS5 em `127.0.0.1:9050`, serviço systemd)
- `chromium-browser`, `curl`, `jq`, `netcat-openbsd`
- Libs nativas do Camoufox (`libgtk-3-0`, `libasound2`, etc.)
- Um venv Python em `~/.camoufox-venv` com `camoufox[geoip]`
- O binário Camoufox + dataset GeoIP (~300 MB, baixado por `python -m camoufox fetch`)

Para reverter:

```bash
./uninstall.sh
```

---

## Uso

### Caminho A — `spoof-browser.sh` (Chromium + UA spoof + Tor)

```bash
./spoof-browser.sh <perfil> [url] [--no-proxy]
```

Exemplos:

```bash
./spoof-browser.sh windows-chrome
./spoof-browser.sh macos-safari https://abrahamjuliot.github.io/creepjs/
./spoof-browser.sh galaxy-s24 https://browserleaks.com
./spoof-browser.sh ubuntu-firefox https://amiunique.org --no-proxy
```

O script cria perfil temporário em `mktemp -d`, troca o User-Agent, ajusta `--window-size`, força DNS pelo SOCKS5 para evitar leaks, e remove o perfil ao fechar (`trap EXIT`).

### Caminho B — `camoufox-spoof.sh` (Camoufox + Tor, **recomendado**)

```bash
./camoufox-spoof.sh <perfil> [url]
USE_TOR=0 ./camoufox-spoof.sh windows     # sem Tor
```

Exemplos:

```bash
./camoufox-spoof.sh windows
./camoufox-spoof.sh macos https://browserleaks.com
./camoufox-spoof.sh linux https://abrahamjuliot.github.io/creepjs/
```

Camoufox é um **Firefox patched em C++** que troca o fingerprint inteiro de forma consistente: `navigator.platform`, `navigator.vendor`, `navigator.userAgentData`, `WebGL UNMASKED_VENDOR/RENDERER`, canvas hash, audio fingerprint, lista de fontes, `Intl`, timezone, geolocalização (casada com o IP do Tor via `geoip=True`).

### Forçar novo IP via Tor

Entre execuções, peça ao Tor um novo circuito:

```bash
./new-tor-circuit.sh
```

(Usa `ControlPort 9051` se disponível; senão faz `systemctl reload tor`.)

---

## Perfis disponíveis

### Caminho A (`spoof-browser.sh`) — 8 perfis

| Perfil | User-Agent (resumo) | Resolução | Plataforma alvo |
|---|---|---|---|
| `windows-chrome` | Chrome/135 em Windows NT 10 | 1920×1080 | `Win32` |
| `windows-edge` | Edge/135 em Windows NT 10 | 1920×1080 | `Win32` |
| `macos-safari` | Safari 17.6 em macOS 10.15.7 | 1440×900 | `MacIntel` |
| `macos-chrome` | Chrome/135 em macOS 10.15.7 | 1440×900 | `MacIntel` |
| `ubuntu-firefox` | Firefox 140 em Ubuntu | 1920×1080 | `Linux x86_64` |
| `iphone-safari` | Safari 26 em iOS 18.6 | 393×852 | `iPhone` |
| `galaxy-s24` | Chrome/135 em Android 14 | 412×915 | `Linux armv8l` |
| `ipad-safari` | Safari 17 em iPadOS 18 | 1024×1366 | `iPad` |

> **Nota Chrome/Edge**: desde 2022 o token de Windows ficou congelado em "Windows NT 10.0" mesmo no Windows 11 — a distinção só vai por Client Hints (`Sec-CH-UA-Platform-Version`).
>
> **Nota Safari**: desde Safari 26 / iOS 26 (set/2025), Apple congelou o token de iOS dentro da UA do Safari em `18_6`.

### Caminho B (`camoufox-spoof.sh`) — 3 perfis

| Perfil | Screen | OS spoofado |
|---|---|---|
| `windows` | 1920×1080 | Windows 11 coerente (UA, fonts, WebGL, audio) |
| `macos` | 2560×1600 | macOS coerente (UA Apple, fontes Apple, etc.) |
| `linux` | 1920×1080 | Linux coerente (Mesa/llvmpipe, fonts Ubuntu) |

Camoufox **não suporta** mobile (iPhone/Android). Para mobile, use Caminho A — porém ciente que será detectado como inconsistente em CreepJS.

---

## Como validar

Depois de abrir o navegador via script, visite **nesta janela**:

| Site | O que checar |
|---|---|
| <https://check.torproject.org> | IP diferente do real (badge verde só aparece no Tor Browser oficial; aqui o que importa é o IP) |
| <https://ipinfo.io/json> | IP / país / ASN de saída do Tor |
| <https://browserleaks.com/javascript> | `navigator.platform`, `screen`, UA, idioma — devem casar com o perfil |
| <https://browserleaks.com/webgl> | `UNMASKED_VENDOR/RENDERER` — só Caminho B casa com OS escolhido |
| <https://browserleaks.com/fonts> | lista de fontes — só Caminho B casa com OS |
| <https://abrahamjuliot.github.io/creepjs/> | **Trust Score + "Lies"** — Caminho B costuma ter Trust > 70 % e zero lies; Caminho A tem 5–15 lies |
| <https://amiunique.org/fingerprint> | entropia / unicidade |
| <https://www.whatismybrowser.com> | parsing humano do UA |

Validar IP via terminal:

```bash
curl --socks5-hostname 127.0.0.1:9050 https://ipinfo.io/json
```

---

## Caminho A vs Caminho B

| | Caminho A (`spoof-browser.sh`) | Caminho B (`camoufox-spoof.sh`) |
|---|---|---|
| Engine | Chromium / Chrome / Brave | Camoufox (Firefox patched) |
| Dependências | só apt | apt + venv Python (~300 MB) |
| Troca UA | ✅ | ✅ |
| Troca `navigator.platform` | ❌ (continua Linux) | ✅ (C++) |
| Troca WebGL / canvas / audio / fonts | ❌ | ✅ coerente via BrowserForge |
| Client Hints (`Sec-CH-UA-*`) | ❌ | ✅ |
| Geo / timezone casados com IP | ❌ | ✅ (`geoip=True`) |
| Perfis mobile (iPhone/Android) | ✅ (mas detectável) | ❌ não suportado |
| Passa em CreepJS | ❌ várias "lies" | ✅ Trust > 70 % típico |
| Velocidade de inicialização | rápido | médio (binário 300 MB) |

**Use Caminho B sempre que possível.** O Caminho A é só para casos onde você quer algo ultra-leve, ou precisa de perfil mobile (sabendo que será detectado).

---

## Limitações

1. **Camoufox não emula iPhone/Android.** Documentação oficial só aceita `os="windows"|"macos"|"linux"`. Para mobile com fingerprint coerente não existe solução FOSS gratuita hoje — alternativas pagas: Multilogin, Dolphin Anty, GoLogin, AdsPower.
2. **Tor é lento e muitos sites bloqueiam exit nodes.** Cloudflare desafia, Google joga CAPTCHA, alguns sites devolvem 403. Para uso geral considere VPN com SOCKS (ex: Mullvad VPN pago).
3. **Listas de proxies grátis (Proxifly, ProxyScrape, Spys) são impráticas.** Sobrevivência < 10 % ao dia, latências enormes, alguns injetam ads/roubam dados.
4. **`--user-agent` no Chromium não atualiza Client Hints** (`navigator.userAgentData`). Sites modernos (Google, anti-bots) detectam essa discrepância. Camoufox atualiza ambos.
5. **`privacy.resistFingerprinting=true` no Firefox sobrescreve UA custom.** Por isso não há um "Caminho Firefox vanilla" no projeto.
6. **WebRTC / DNS podem vazar IP real.** Caminho A mitiga com `--host-resolver-rules`; Caminho B mitiga com defaults do Camoufox (`block_webrtc`).
7. **Mullvad Browser e Tor Browser não servem** para este caso — eles homogeneízam todos os usuários no MESMO fingerprint, não deixam você fingir ser outro dispositivo.
8. **Anti-bots enterprise (DataDome, PerimeterX, Kasada, Cloudflare BM) detectam Camoufox.** O objetivo realista deste projeto é despistar tracking publicitário e sites comuns, **não** burlar anti-bot enterprise.
9. **User-Agents envelhecem**. Chrome/Firefox sobem versão a cada 4 semanas. Recalibre as strings em `spoof-browser.sh` periodicamente. Fonte boa: <https://jnrbsn.github.io/user-agents/user-agents.json>.

---

## Estrutura do projeto

```
ghost-browser/
├── README.md              # este arquivo
├── LICENSE                # MIT
├── .gitignore
├── install.sh             # apt + venv + camoufox fetch
├── uninstall.sh           # remove venv + cache; pergunta sobre apt
├── spoof-browser.sh       # Caminho A — Chromium + Tor + UA (8 perfis)
├── camoufox-spoof.sh      # Caminho B — Camoufox + Tor (3 perfis desktop)
└── new-tor-circuit.sh     # força novo IP via SIGNAL NEWNYM
```

---

## Licença

MIT. Veja [`LICENSE`](LICENSE).

---

## Aviso ético

Este projeto tem fins **educacionais** (QA, pesquisa de privacidade, automação de tarefas próprias, testes anti-fingerprint). Burlar termos de uso de serviços, mecanismos anti-fraude ou jurisdições onde Tor é restrito pode ser ilegal. Responsabilidade do operador.
