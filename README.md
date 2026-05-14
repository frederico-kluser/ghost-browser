<p align="center">
  <img src="logo.jpg" alt="ghost-browser" width="220"/>
</p>

<h1 align="center">ghost-browser</h1>

> **Sua sessão. Seu IP. Seu fingerprint. Sua escolha.**
>
> Um navegador descartável, isolado, com IP rotacionado pelo Tor e fingerprint coerente trocado em nível C++. Linux (Debian/Arch/Fedora + Flatpak fallback) e macOS. Bash. Sem telemetria. Sem conta. Sem rastro.

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
| Proxy / VPN customizado | env var `PROXY=socks5://...` sobrescreve Tor default; `PROXY=none` desliga proxy |
| Identidade persistente | env var `KEEP=nome` salva perfil em `~/.ghost-browser/profiles/<nome>/` com OS fixado |

E o que **não** dá pra resolver com esta stack — sendo honesto:

- **Anti-bot enterprise** (Cloudflare Bot Management, DataDome, PerimeterX, Kasada). Esses caras analisam TLS JA3, HTTP/2 frame ordering, comportamento de mouse com ML. Camoufox melhora mas não esconde. Se você precisa passar por isso, vai pagar GoLogin, Multilogin, AdsPower — não é missão deste repo.
- **Mobile fingerprint coerente.** Camoufox só suporta desktop (`windows`/`macos`/`linux`). Removemos os perfis iPhone/iPad/Android do projeto para não dar falsa sensação de proteção — qualquer anti-bot detectava como inconsistente.
- **Identidade externa.** Se o site quer SMS/e-mail único, você precisa de [addy.io](https://addy.io), [SimpleLogin](https://simplelogin.io), número descartável. Fora do escopo.

---

## Instalação

`install.sh` detecta S.O. **e distro** automaticamente. Mesmo comando nas três famílias Linux principais e no macOS:

```bash
./install.sh
```

### Plataformas suportadas

| Família | Distros confirmadas | Package manager |
|---|---|---|
| Debian | Ubuntu, Pop!_OS, Debian, Mint | `apt` |
| Arch | Arch, Manjaro, EndeavourOS, CachyOS | `pacman` |
| Fedora | Fedora, Nobara, RHEL, Rocky, AlmaLinux | `dnf` |
| macOS | macOS 13+ | `brew` (Homebrew obrigatório) |

> Camoufox traz Firefox bundled — não há dependência de navegador do sistema. Em qualquer distro Linux com `tor`, `python3` e libs GTK/X11 básicas, o `ghost.sh` funciona.

### Requisitos por S.O.

**Linux** — usa `sudo` na primeira execução pro package manager nativo (`apt`/`pacman`/`dnf`) e `systemctl`.

**macOS** — requer [Homebrew](https://brew.sh) **pré-instalado**; o `install.sh` orienta o usuário caso esteja faltando. Não usa `sudo` (brew dispensa root).

O `install.sh` é idempotente e fala muito. Ele instala (só o que falta):

- `tor` (proxy SOCKS5 em `127.0.0.1:9050`) — `systemd` no Linux, `brew services` no macOS
- Libs runtime do Camoufox (nomes diferem por distro: `libgtk-3-0t64` no Debian, `gtk3` no Arch/Fedora, etc.). macOS dispensa — Camoufox usa Firefox Cocoa nativo.
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

Remove venv, cache do Camoufox (XDG no Linux ou `~/Library/Caches/camoufox` no macOS), perfis temporários, e pergunta antes de remover pacotes (só o que foi rastreado em `~/.cache/ghost-browser/installed-pkgs`). Se houver perfis persistentes em `~/.ghost-browser/profiles/`, também pergunta interativamente antes de apagá-los.

---

## Uso

### Forma básica

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

### Receitas comuns

```bash
# padrão: Tor + OS aleatório + perfil descartável
./ghost.sh https://site.com

# usando VPN própria (Mullvad, ProtonVPN paga, qualquer SOCKS5/HTTP)
PROXY=socks5://10.2.0.1:1080 ./ghost.sh

# sem proxy (IP real, mas fingerprint trocado) — útil para sites internos
PROXY=none ./ghost.sh

# força um OS específico (sem aleatório)
GHOST_OS=macos ./ghost.sh

# identidade persistente "trabalho" (cookies + OS fixos entre sessões)
KEEP=trabalho ./ghost.sh https://gmail.com

# cria identidade nova com OS escolhido manualmente
KEEP=pessoal GHOST_OS=windows ./ghost.sh
```

### Variáveis de ambiente

| Variável | Valores | Efeito |
|---|---|---|
| `PROXY` | `tor` (default) \| `none` \| `socks5://host:port` \| `http://host:port` \| `https://host:port` | Sobrescreve o proxy Tor padrão. `none` desliga proxy (usa IP real). |
| `KEEP` | qualquer nome `[A-Za-z0-9_-]+` | Salva o perfil em `~/.ghost-browser/profiles/<nome>/`. OS é fixado na primeira vez. Sem `KEEP`, o perfil é descartado no fim. |
| `GHOST_OS` | `windows` \| `macos` \| `linux` (aceita maiúsculas; é normalizado para lowercase) | Força um OS específico (sem sorteio). Combinado com `KEEP`, fixa o OS persistente. |
| `USE_TOR` (legado) | `0` | Alias de `PROXY=none`. Mantido por compat com docs antigas. |

> **Schemes de proxy aceitos:** `socks5://`, `http://`, `https://`. O Playwright (engine do Camoufox) não suporta `socks4://` oficialmente — usar `socks4://` resulta em erro do Camoufox.

> **Privacidade com `PROXY=none`:** quando você desliga o proxy, o `ghost.sh` também desativa `geoip` automaticamente. Sem isso, Camoufox tentaria buscar seu IP real em `api.ipify.org` (ou fallback) para casar locale/timezone — o que vazaria o IP que você quer esconder. Trade-off: sem `geoip`, locale/timezone do Firefox podem não bater com sua região, mas seu IP real fica em casa.

> **Perfil persistente em paralelo:** Firefox usa um arquivo `parent.lock` dentro do `user_data_dir`. Rodar `KEEP=foo ./ghost.sh` duas vezes simultaneamente faz a segunda instância travar com timeout. Use nomes diferentes (`KEEP=foo` + `KEEP=bar`) para rodar em paralelo.

### Helpers

- **`./new-tor-circuit.sh`** — força IP novo entre execuções. Já é chamado pelo `ghost.sh` quando o proxy é Tor. Pra rodar standalone, abra `ControlPort 9051` no torrc (caminho depende do S.O. — Linux: `/etc/tor/torrc`; macOS: `$(brew --prefix)/etc/tor/torrc`). Veja a seção "Configuração do ControlPort do Tor" acima.

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

## Comparação: ghost-browser vs Tor Browser

| | `ghost-browser` (este repo) | Tor Browser oficial |
|---|---|---|
| Engine | Camoufox (Firefox patched em C++) | Firefox ESR + patches Tor |
| Filosofia | Você finge ser outro device | Você se uniformiza com todo mundo |
| Troca UA | ✅ | n/a (todos têm o mesmo) |
| Troca `navigator.platform` | ✅ | ✅ (mas todo mundo tem o mesmo) |
| Troca WebGL/canvas/audio/fonts | ✅ coerente via BrowserForge | ✅ via resistFingerprinting (zeros) |
| Client Hints (`Sec-CH-UA-*`) | ✅ | ✅ |
| Geo/timezone casados com IP | ✅ (`geoip=True`) | uniforme |
| Proxy customizado (VPN, etc.) | ✅ (`PROXY=socks5://...`) | ❌ (só Tor) |
| Identidade persistente entre sessões | ✅ (`KEEP=nome`) | ❌ (sempre descartável) |
| Perfis mobile | ❌ (Camoufox não suporta) | ❌ |
| Passa em CreepJS | ✅ Trust >70% típico | ✅ Trust ~80% (homogêneo) |
| Dependências | apt + venv (~300 MB) | bundle pronto |

**Use `ghost.sh`** quando quiser **identidade trocada** (parecer outra pessoa específica, com cookies/sessão controláveis). Use **Tor Browser** quando quiser **anonimato uniforme** (se misturar com a multidão, sem variação entre você e os outros usuários).

---

## Estrutura

```
ghost-browser/
├── README.md              # este arquivo
├── FIXES.md               # histórico de bugs corrigidos (todos fechados)
├── LICENSE                # MIT
├── logo.jpg               # mascote (fantasma minimalista, mono)
├── .gitignore
├── install.sh             # auto-detecta S.O. + distro Linux (Debian/Arch/Fedora);
│                          # instala Tor, libs Camoufox, venv Python; resumo [+]/[=]/[!] no fim
├── uninstall.sh           # remove venv/cache/perfis; pergunta antes de remover pacotes;
│                          # também pergunta antes de apagar perfis persistentes em ~/.ghost-browser/
├── ghost.sh               # ★ super-comando: PROXY/KEEP/GHOST_OS via env, Camoufox+Tor por default
├── new-tor-circuit.sh     # força SIGNAL NEWNYM (ControlPort 9051) ou reload do serviço
└── lib/platform.sh        # detecção de S.O. + distro + dispatch de package manager
                           # (apt/pacman/dnf/brew); bash 3.2 portable

# estado (não versionado):
~/.ghost-browser/profiles/  # perfis persistentes criados por KEEP=nome
~/.camoufox-venv/           # venv com Camoufox + BrowserForge + GeoIP
~/.cache/ghost-browser/     # track-file de pacotes instalados pelo install.sh
```

---

## Limitações & honestidade

1. **Não é silver bullet.** Anti-bot enterprise (Cloudflare BM, DataDome) detecta Camoufox via TLS/HTTP-2 fingerprint. Esta stack mira tracking publicitário e cadastros normais — não nações-estado, não Akamai-fronted login flows.
2. **Tor é lento.** Em média 5–15s pra primeira requisição. Cloudflare desafia exit nodes. Se um site bloquear, troque por VPN própria: `PROXY=socks5://seu-vpn:1080 ./ghost.sh`.
3. **User-Agents envelhecem.** O Camoufox/BrowserForge atualizam UAs automaticamente. Pra puxar o dataset mais recente: `source ~/.camoufox-venv/bin/activate && python -m camoufox fetch`.
4. **Mullvad Browser e Tor Browser homogeneízam, não personificam.** Útil pra ler anonimamente, inútil pra cadastrar como "outro alguém".
5. **WebRTC permanece bloqueado pelo Camoufox** (`block_webrtc=True`) mesmo com `PROXY=none`, mas DNS lookups vão pelo seu resolver local — sua máquina aparece como Linux normal para o ISP nesse modo.
6. **Camoufox não emula iPhone/Android.** Documentação oficial só aceita `os="windows"|"macos"|"linux"`. Pra mobile coerente, alternativas pagas: GoLogin, Multilogin, AdsPower.

---

## Troubleshooting

### Perfil persistente não abre depois de um crash / `kill -9`

Firefox deixa um `parent.lock` (e/ou `.parentlock`) dentro do `user_data_dir`. Se você matou o processo no `kill -9` ou o sistema travou, o lock fica órfão e a próxima execução fica esperando.

```bash
# checar
ls -la ~/.ghost-browser/profiles/<nome>/ | grep -i lock
# limpar (com o ghost.sh fechado)
rm -f ~/.ghost-browser/profiles/<nome>/parent.lock \
      ~/.ghost-browser/profiles/<nome>/.parentlock
```

### Tor não sobe / `[!] Tor não responde em 127.0.0.1:9050`

```bash
# Linux
sudo systemctl status tor
sudo systemctl restart tor
journalctl -u tor@default | tail -20

# macOS
brew services info tor
brew services restart tor
```

Se o ISP está bloqueando Tor, use `PROXY=socks5://seu-vpn:1080 ./ghost.sh` com uma VPN.

### `[!] PROXY inválido` mas o valor parece correto

Confira os schemes aceitos: `tor`, `none`, `socks5://`, `http://`, `https://`. `socks4://` não é suportado pelo Playwright.

### Camoufox `InvalidIP: Failed to get IP address` com proxy custom

Significa que o proxy custom (VPN/SOCKS) não está respondendo. Teste manualmente:

```bash
curl -s --socks5-hostname <vpn-host>:<port> https://api.ipify.org
```

Se não retorna IP, o proxy está fora. Volte ao Tor (`PROXY=tor`) ou conserte o VPN.

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
