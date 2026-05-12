# ghost-browser

> **Sua sessão. Seu IP. Seu fingerprint. Sua escolha.**
>
> Um navegador descartável, isolado, com IP rotacionado pelo Tor e fingerprint coerente trocado em nível C++. Linux. Bash. Sem telemetria. Sem conta. Sem rastro.

```bash
./install.sh   # uma vez
./ghost.sh     # toda vez que você quiser uma identidade nova
```

---

## Por que isto existe

A web de 2026 não te trata como visitante. Te trata como **target**. Cada `fetch()` que seu browser faz num site arbitrário sai com:

- IP público (resolvível pra cidade, ISP, AS, e muitas vezes pra você como pessoa)
- Canvas hash, WebGL renderer, audio fingerprint, lista de fontes, screen + colorDepth, `Intl.timeZone`, `navigator.platform`, Client Hints, `userAgentData.brands`
- Cookies, localStorage, IndexedDB, ServiceWorker caches, ETags persistentes
- TLS JA3/JA4, HTTP/2 SETTINGS frame fingerprint, ordem de headers

Combinando esses sinais, um único site identifica você unicamente em **>99% das visitas** ([Panopticlick](https://amiunique.org), [FingerprintJS](https://fingerprint.com)). Cookie-clearing, modo anônimo e VPN básica resolvem **nenhum** dos vetores acima.

**ghost-browser** é o oposto político disso: uma stack curta de scripts shell que monta, antes de cada sessão, uma máquina virtual de identidade — IP, fingerprint, locale, geo, timezone — coerente o suficiente pra passar em CreepJS com Trust >70% e descartável o suficiente pra desaparecer no `Ctrl+C`.

Isso não é furtar. Isso é **se recusar a pagar com seus dados** o pedágio que sites cobram pra te deixar entrar. É o mesmo princípio das listas de domínio do uBlock Origin, do Tor Project, do EFF Privacy Badger, do Mullvad VPN: na ausência de uma lei honesta de privacidade, você se defende sozinho.

> "Privacy is necessary for an open society in the electronic age. Privacy is not secrecy."
> — Eric Hughes, *A Cypherpunk's Manifesto* (1993)

---

## TL;DR

```bash
git clone https://github.com/frederico-kluser/ghost-browser
cd ghost-browser
./install.sh
./ghost.sh
```

`ghost.sh` te pergunta a URL, sorteia um OS pra spoofar (windows/macos/linux), força um novo circuito Tor, abre um Firefox-patched (Camoufox) com fingerprint coerente, **nega GPS silenciosamente** e apaga tudo (perfil temporário, browser, processo) no momento que você fecha o navegador, dá Ctrl+C ou fecha o terminal.

---

## O que rola debaixo do capô

| Vetor | Defesa |
|---|---|
| IP / ASN / geo | Tor SOCKS5 em `127.0.0.1:9050`, novo circuito por sessão via `new-tor-circuit.sh` |
| Cookies, storage, cache | Perfil em `mktemp -d`, apagado por `trap INT TERM HUP EXIT` |
| Canvas / WebGL / Audio / Fonts | Camoufox patcha em C++ (Firefox fork da [BrowserForge](https://github.com/daijro/camoufox)) |
| `navigator.platform`, Client Hints, `userAgentData` | Camoufox `os="windows"\|"macos"\|"linux"` — coerentes entre si |
| `Intl.timeZone`, `navigator.language` | Camoufox `geoip=True` → bate com cidade do exit Tor (dataset MaxMind) |
| WebRTC IP leak | Camoufox `block_webrtc=True` (default) |
| HTML5 Geolocation API | `firefox_user_prefs={"permissions.default.geo": 2}` → site recebe `PERMISSION_DENIED` sem prompt |
| Botão "X" do navegador | `BrowserContext.wait_for_event("close")` → encerra script + apaga perfil |

E o que **não** dá pra resolver com esta stack — sendo honesto:

- **Anti-bot enterprise** (Cloudflare Bot Management, DataDome, PerimeterX, Kasada). Esses caras analisam TLS JA3, HTTP/2 frame ordering, comportamento de mouse com ML. Camoufox melhora mas não esconde. Se você precisa passar por isso, vai pagar GoLogin, Multilogin, AdsPower — não é missão deste repo.
- **Mobile fingerprint coerente.** Camoufox só desktop. `spoof-browser.sh` tem perfis iPhone/Android mas CreepJS detecta como inconsistente.
- **Identidade externa.** Se o site quer SMS/e-mail único, você precisa de [addy.io](https://addy.io), [SimpleLogin](https://simplelogin.io), número descartável. Fora do escopo.

---

## Instalação

Funciona em **Ubuntu/Debian/Pop!_OS 22.04+** (via `apt`) e **macOS 13+** (via Homebrew). O `install.sh` detecta o S.O. automaticamente — mesmo comando nos dois:

```bash
./install.sh
```

### Requisitos por S.O.

**Linux** — usa `sudo` na primeira execução para `apt` e `systemctl`.

**macOS** — requer [Homebrew](https://brew.sh) **pré-instalado**; o `install.sh` orienta o usuário caso esteja faltando. Não usa `sudo` (brew dispensa root).

O `install.sh` é idempotente e fala muito. Ele instala (só o que falta):

- `tor` (proxy SOCKS5 em `127.0.0.1:9050`) — serviço `systemd` no Linux, `brew services` no macOS
- Um navegador Chromium-family — em Linux com `snapd`, instala Chromium do snap; em Pop!_OS/Debian sem snap, baixa chave GPG oficial da Brave e adiciona o repo apt; em macOS, instala `chromium` via Homebrew Cask se nenhum (Chromium/Brave/Chrome/Edge) já estiver em `/Applications`
- Linux apenas: libs nativas do Camoufox (`libgtk-3-0t64`, `libasound2t64`, `libdbus-glib-1-2`, `libx11-xcb1`). macOS dispensa — Camoufox usa Firefox Cocoa nativo
- venv Python em `~/.camoufox-venv` com `camoufox[geoip]`
- binário Camoufox (Firefox patched) + dataset GeoIP (~300 MB)
- valida saída Tor em endpoints Tor-friendly (`check.torproject.org`, `api.ipify.org`)

No fim, imprime um **resumo categorizado**: `[+]` instalado agora, `[=]` já presente, `[!]` falhou. Se algo está em `[!]`, [veja FIXES.md](FIXES.md) para diagnóstico.

### Configuração do ControlPort do Tor (opcional, mas recomendado)

Sem ControlPort 9051, `new-tor-circuit.sh` cai para um reload do serviço Tor — funciona mas é mais lento e fecha conexões em andamento. Para habilitar a troca rápida de circuito:

- **Linux**: edite `/etc/tor/torrc` adicionando `ControlPort 9051` + `CookieAuthentication 0`, depois `sudo systemctl restart tor`.
- **macOS**: `brew install tor` deixa apenas `torrc.sample`. Crie o `torrc` primeiro:
  ```bash
  cp "$(brew --prefix)/etc/tor/torrc.sample" "$(brew --prefix)/etc/tor/torrc"
  printf '\nControlPort 9051\nCookieAuthentication 0\n' >> "$(brew --prefix)/etc/tor/torrc"
  brew services restart tor
  ```

Reverter tudo:

```bash
./uninstall.sh
```

Remove venv, cache do Camoufox (XDG no Linux ou `~/Library/Caches/camoufox` no macOS), perfis temporários, e pergunta antes de remover pacotes (só o que foi rastreado em `~/.cache/ghost-browser/installed-pkgs`). Se Brave foi instalado por nós no Linux, também limpa o source list apt e a chave GPG. No macOS, casks instalados por nós (ex.: `chromium`) também são removidos.

---

## Uso

### Caminho principal — `./ghost.sh`

```bash
./ghost.sh                            # pergunta URL interativamente
./ghost.sh https://site.com/signup    # one-liner
./ghost.sh youtube.com                # esquema é opcional, prepende https://
```

Cada execução:

1. Detecta S.O. e inicia o Tor se ele estiver parado (`systemctl start tor` no Linux, `brew services start tor` no macOS).
2. Força novo circuito Tor (`SIGNAL NEWNYM` se ControlPort estiver aberto, senão reload do serviço).
3. Sorteia OS spoofado (`windows` | `macos` | `linux`).
4. Cria perfil descartável em `$TMPDIR/ghost-XXXXXX` (`/tmp/...` no Linux, `/var/folders/.../ghost-...` no macOS).
5. Abre Camoufox com fingerprint coerente + Tor + GPS negado silenciosamente.
6. Bloqueia até você fechar o navegador.
7. Apaga o perfil no exit (Ctrl+C, X do terminal, X do navegador, kill, crash — tudo).

Pra pular o Tor (testes locais), use `USE_TOR=0 ./camoufox-spoof.sh <os> <url>` — o `ghost.sh` é Tor-first por design.

### Caminhos alternativos

- **`./camoufox-spoof.sh <windows|macos|linux> [url]`** — mesma engine do `ghost.sh`, sem OS aleatório, sem prompt; espera ENTER no terminal pra encerrar. Útil pra pinar OS.
- **`./spoof-browser.sh <perfil> [url] [--no-proxy]`** — Caminho A, leve, Chromium/Brave + UA spoof. 8 perfis (`windows-chrome`, `macos-safari`, `iphone-safari`, `galaxy-s24`, etc.). Não tem fingerprint coerente — vai vazar `navigator.platform=Linux` em CreepJS. Útil pra perfis mobile (detectáveis, mas existem).
- **`./new-tor-circuit.sh`** — força IP novo entre execuções. Já é chamado pelo `ghost.sh`. Pra rodar standalone, abra `ControlPort 9051` no torrc (caminho depende do S.O. — Linux: `/etc/tor/torrc`; macOS: `$(brew --prefix)/etc/tor/torrc`). Veja a seção "Configuração do ControlPort do Tor" acima.

---

## Validar que funcionou

Abre essas URLs **dentro** da janela aberta pelo `ghost.sh`:

| Site | O que checar |
|---|---|
| [check.torproject.org](https://check.torproject.org) | IP é exit Tor (a badge verde "Congratulations" só aparece no Tor Browser oficial; aqui o que importa é o IP retornado bater com o de saída) |
| [ipinfo.io/json](https://ipinfo.io/json) | IP, país, ASN do exit |
| [browserleaks.com/javascript](https://browserleaks.com/javascript) | `navigator.platform`, screen, UA — devem casar com OS sorteado |
| [browserleaks.com/webgl](https://browserleaks.com/webgl) | `UNMASKED_VENDOR/RENDERER` — Camoufox spoofa coerente |
| [browserleaks.com/fonts](https://browserleaks.com/fonts) | Lista de fontes do OS spoofado, não do seu Linux real |
| [browserleaks.com/geo](https://browserleaks.com/geo) | "Permission denied" — GPS negado sem prompt |
| [abrahamjuliot.github.io/creepjs](https://abrahamjuliot.github.io/creepjs/) | **Trust Score >70% e zero "lies"** — métrica de ouro |
| [amiunique.org/fingerprint](https://amiunique.org/fingerprint) | Entropia / unicidade |

Validar IP no terminal:

```bash
curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
# {"IsTor":true,"IP":"107.189.5.121"}
```

---

## Comparação: Caminho A vs Caminho B vs Tor Browser

| | Caminho A (`spoof-browser.sh`) | Caminho B (`ghost.sh` / `camoufox-spoof.sh`) | Tor Browser oficial |
|---|---|---|---|
| Engine | Chromium / Brave | Camoufox (Firefox patched em C++) | Firefox ESR + patches Tor |
| Filosofia | Você finge ser outro device | Você finge ser outro device | Você se uniformiza com todo mundo |
| Troca UA | ✅ | ✅ | n/a (todos têm o mesmo) |
| Troca `navigator.platform` | ❌ (continua "Linux") | ✅ | ✅ (mas todo mundo tem o mesmo) |
| Troca WebGL/canvas/audio/fonts | ❌ | ✅ coerente via BrowserForge | ✅ via resistFingerprinting (zeros) |
| Client Hints (`Sec-CH-UA-*`) | ❌ | ✅ | ✅ |
| Geo/timezone casados com IP | ❌ | ✅ (`geoip=True`) | uniforme |
| Perfis mobile | ✅ (detectáveis) | ❌ | ❌ |
| Passa em CreepJS | ❌ várias "lies" | ✅ Trust >70% típico | ✅ Trust ~80% (homogêneo) |
| Dependências | só apt | apt + venv (~300 MB) | bundle pronto |
| Velocidade | rápido | médio | médio |

**Use `ghost.sh` por padrão.** Use `spoof-browser.sh` só pra perfis mobile sabendo que é detectável. Use Tor Browser quando quiser **anonimato uniforme** (se misturar com a multidão) em vez de **identidade trocada** (parecer outra pessoa).

---

## Estrutura

```
ghost-browser/
├── README.md              # este arquivo
├── FIXES.md               # bugs conhecidos + workarounds atuais
├── LICENSE                # MIT
├── .gitignore
├── install.sh             # auto-detecta S.O. — apt+Brave repo no Linux, brew+cask no macOS
├── uninstall.sh           # remove venv/cache; pergunta sobre pacotes; limpa repos do Linux
├── ghost.sh               # ★ super-comando: pergunta URL, OS aleatório, GPS negado, cleanup total
├── camoufox-spoof.sh      # Caminho B manual (escolhe OS, ENTER pra fechar)
├── spoof-browser.sh       # Caminho A (Chromium/Brave + UA spoof, 8 perfis incl. mobile)
├── new-tor-circuit.sh     # força SIGNAL NEWNYM (ControlPort 9051) ou reload do serviço
└── lib/platform.sh        # detecção de S.O. + helpers brew/apt/systemd/launchd
```

---

## Perfis Caminho A

| Perfil | UA | Resolução |
|---|---|---|
| `windows-chrome` | Chrome/135 em Windows NT 10 | 1920×1080 |
| `windows-edge` | Edge/135 em Windows NT 10 | 1920×1080 |
| `macos-safari` | Safari 17.6 em macOS | 1440×900 |
| `macos-chrome` | Chrome/135 em macOS | 1440×900 |
| `ubuntu-firefox` | Firefox 140 em Ubuntu | 1920×1080 |
| `iphone-safari` | Safari 26 em iOS 18.6 | 393×852 |
| `galaxy-s24` | Chrome/135 em Android 14 | 412×915 |
| `ipad-safari` | Safari 17 em iPadOS 18 | 1024×1366 |

---

## Limitações & honestidade

1. **Não é silver bullet.** Anti-bot enterprise (Cloudflare BM, DataDome) detecta Camoufox via TLS/HTTP-2 fingerprint. Esta stack mira tracking publicitário e cadastros normais — não nações-estado, não Akamai-fronted login flows.
2. **Tor é lento.** Em média 5–15s pra primeira requisição. Cloudflare desafia exit nodes. Se um site bloquear, alternativa é trocar `socks5://127.0.0.1:9050` por SOCKS de VPN paga (Mullvad, IVPN) no `ghost.sh` linha ~80.
3. **User-Agents envelhecem.** Recalibre as strings em `spoof-browser.sh` a cada ~3 meses. Fonte boa: [jnrbsn.github.io/user-agents/user-agents.json](https://jnrbsn.github.io/user-agents/user-agents.json).
4. **Mullvad Browser e Tor Browser homogeneízam, não personificam.** Útil pra ler anonimamente, inútil pra cadastrar como "outro alguém".
5. **WebRTC vaza IP local em modo `--no-proxy`.** Sempre que o Tor for desativado, considere que sua máquina está exposta como Linux normal.
6. **Camoufox não emula iPhone/Android.** Documentação oficial só aceita `os="windows"|"macos"|"linux"`. Pra mobile coerente, alternativas pagas: GoLogin, Multilogin, AdsPower.

---

## Bugs conhecidos

Nenhum em aberto até 12/05/2026. Os 3 bugs originais (teste de Tor com `ipinfo.io`, ausência de Chromium em Pop!_OS sem snap, `TypeError` do Camoufox 0.4.11) estão **todos fechados** — histórico técnico completo em [FIXES.md](FIXES.md).

Se algo quebrar depois de uma atualização do Camoufox, Firefox ou Tor: abra issue no GitHub com o stacktrace e o resumo do `./install.sh`.

---

## Manifesto curto

Privacy não é sobre esconder. É sobre **escolher** o que mostrar, pra quem, e quando. Sites que coletam fingerprint sem te perguntar quebraram esse contrato primeiro. Esta ferramenta é uma resposta proporcional.

Não promove fraude. Não burla mecanismos de pagamento. Não invade sistemas. Faz uma coisa só: te devolve o controle de qual identidade seu browser apresenta ao internet.

A legalidade depende de jurisdição e de termos-de-uso do destino. Em quase todos os lugares civilizados, **trocar UA, IP e fingerprint é permitido**. Burlar ToS é cinza. Fraude documental é crime — em qualquer lugar, com ou sem esta ferramenta. **Você é o operador, você assume as consequências.** Esta linha não tem como ser apagada por boa intenção do dev.

---

## Inspirações & afins

- [Tor Project](https://www.torproject.org/) — o original
- [Camoufox](https://github.com/daijro/camoufox) — Firefox C++ patched, faz o trabalho pesado
- [BrowserForge](https://github.com/daijro/browserforge) — fingerprints coerentes
- [EFF Privacy Badger](https://privacybadger.org/), [uBlock Origin](https://ublockorigin.com/), [Mullvad VPN](https://mullvad.net/)
- [Cypherpunks Manifesto](https://www.activism.net/cypherpunk/manifesto.html), [Crypto Anarchist Manifesto](https://www.activism.net/cypherpunk/crypto-anarchy.html)
- [EFF Cover Your Tracks](https://coveryourtracks.eff.org/) — entenda o quanto você vaza

---

## Licença

MIT. Faça fork. Faça merge. Mande PR. Mande issue. Se algo quebrar com uma atualização do Camoufox/Firefox, abra issue com o stacktrace — esta stack vai precisar de manutenção contínua porque o lado adversário também não dorme.

> "If privacy is outlawed, only outlaws will have privacy."
> — Phil Zimmermann (criador do PGP)
