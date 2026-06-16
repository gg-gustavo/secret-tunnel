---
marp: true
theme: gaia
paginate: true
backgroundColor: #fbfbfe
color: #1a1a2e
header: 'Túnel Secreto · P4 / Intel Tofino'
footer: 'Redes 1 — 2026/1'
style: |
  section {
    font-size: 26px;
  }
  h1 { color: #2d2a6e; }
  h2 { color: #3a37a0; }
  code { background: #ecebfb; }
  strong { color: #2d2a6e; }
  table { font-size: 22px; }
  blockquote {
    border-left: 6px solid #6c63ff;
    padding-left: 0.6em;
    color: #333;
  }
---

<!-- _class: lead -->
<!-- _paginate: false -->

# 🔐 Túnel Secreto

### Filtragem de pacotes por token dentro de um switch programável

**P4 · Arquitetura PISA · Simulador Intel Tofino**

<br>

Redes 1 — 2026/1

---

<!-- _class: lead -->

## O problema

Queremos transformar um switch em um **porteiro com senha**.

> Um pacote só é roteado para o destino se carregar um **token secreto de
> 16 bytes** idêntico ao que foi gravado na memória do switch.

Como não temos o hardware, usamos um **simulador do chip Intel Tofino**,
que implementa a arquitetura **PISA** de switches programáveis.

---

## A ideia em uma figura

```
 GRAVAR token (0x9000)
 veth0 ───────────────►  [ SWITCH ] grava token e descarta  ──X

 MENSAGEM com token ERRADO (0x9001)
 veth0 ───────────────►  [ SWITCH ]  ──X  (dropado)

 MENSAGEM com token CERTO (0x9001)
 veth0 ───────────────►  [ SWITCH ]  ─────►  veth8 (destino)
```

`0x9000` / `0x9001` = **EtherTypes** que escolhemos para diferenciar
"estou gravando" de "estou enviando".

---

## O que é P4?

**P4** = linguagem que programa o que o switch faz com **cada pacote**.

| | **Plano de Dados** | **Plano de Controle** |
|--|--------------------|------------------------|
| O quê | processa **cada pacote** | **configura** o switch |
| Velocidade | altíssima (line rate) | lenta (CPU comum) |
| Escrito em | **P4** | Python (`setup.py`) |
| Quando roda | por pacote | de vez em quando |

> O enunciado diz: **não precisamos mexer no plano de controle.**
> Todo o trabalho está nos arquivos `.p4`.

---

## PISA: o switch é uma "esteira"

```
        INGRESS (entrada)              EGRESS (saída)
   ┌───────────────────────┐  ┌──┐  ┌───────────────────────┐
 → │ Parser → Match-Action │→ │TM│→ │ Parser → … → Deparser │ →
   │          → Deparser    │  └──┘  └───────────────────────┘
   └───────────────────────┘
     ler → decidir → remontar       fila      ler → remontar
```

- **Parser**: lê os bytes e os organiza em cabeçalhos.
- **Match-Action**: procura (match) e executa (action) — a lógica.
- **Deparser**: remonta os cabeçalhos em bytes para a saída.

> Sem loops, sem voltar: é isso que garante a velocidade — e impõe as
> limitações que veremos.

---

## As "regras duras" do hardware

| Em C você faz… | Em P4… |
|----------------|--------|
| `while`, `for`, recursão | ❌ sem loops |
| `malloc` | ❌ memória é fixa |
| ler variável N vezes | ⚠️ registrador: **1 acesso/pacote** |
| `int`, `char` | `bit<N>` — tamanho **exato** |
| `a && b && c && d` | ⚠️ pode ser "complexo demais" |

> 💡 Essas duas regras explicam **os dois truques** do nosso código:
> **4 registradores** e **`if`s aninhados**.

---

## A arquitetura do nosso programa

Três arquivos, três papéis:

| Arquivo | Papel |
|---------|-------|
| `headers.p4` | define os **formatos** dos cabeçalhos |
| `parser.p4` | ensina o switch a **ler** o token |
| `secret.p4` | o **cérebro**: gravar, validar, rotear, dropar |

\+ `test_tunnel.py` — fabrica e envia os pacotes de teste (Scapy).

---

## O cabeçalho secreto (`headers.p4`)

```p4
header secret_h {
    bit<128> token;     // 16 bytes, exatamente o pedido
}

struct header_t {
    ethernet_h ethernet;
    secret_h   secret;  // ADICIONADO no trabalho
}
```

> Um `header` é como uma `struct` de C com tamanho de bit exato —
> e um bit escondido de "estou presente neste pacote?".

---

## Ler o token (`parser.p4`)

O parser é uma **máquina de estados** (pense em `switch` + `goto`):

```p4
state parse_ethernet {
    pkt.extract(hdr.ethernet);
    transition select(hdr.ethernet.ether_type) {
        0x9000: parse_secret;   // pacote de gravação
        0x9001: parse_secret;   // pacote de mensagem
        default: accept;        // sem token → para aqui
    }
}
state parse_secret {
    pkt.extract(hdr.secret);    // lê os 16 bytes do token
    transition accept;
}
```

---

<!-- _class: lead -->

## O cérebro: 3 fluxos

| EtherType | Significado | Ação do switch |
|-----------|-------------|----------------|
| **0x9000** | "grave este token" | escreve nos registradores + **dropa** |
| **0x9001** | "mensagem com token" | compara; igual **roteia**, diferente **dropa** |
| **outros** | tráfego comum | **dropa** (nega por padrão) |

---

## Fluxo A — Gravação (`0x9000`)

```p4
secret_reg1.write(0, hdr.secret.token[31:0]);
secret_reg2.write(0, hdr.secret.token[63:32]);
secret_reg3.write(0, hdr.secret.token[95:64]);
secret_reg4.write(0, hdr.secret.token[127:96]);

ig_dprsr_md.drop_ctl = 1;   // config não segue adiante
```

- O token (128 bits) é **fatiado** em 4 pedaços de 32 bits.
- Cada pedaço vai para um **registrador** (memória que persiste).
- O pacote de configuração é **descartado** — cumpriu seu papel.

---

## Fluxo B — Validação (`0x9001`)

```p4
meta.aux1 = secret_reg1.read(0);   // lê a memória
...                                 // (4 registradores)

if (token[31:0]   == meta.aux1)
 if (token[63:32]  == meta.aux2)
  if (token[95:64]  == meta.aux3)
   if (token[127:96] == meta.aux4)
        forward.apply();   // TUDO casou → roteia!
   else  ... drop ...      // qualquer diferença → dropa
```

> Compara o token do **pacote** com o token **guardado**, pedaço a pedaço.

---

## Os dois truques de hardware

**1. Por que 4 registradores?**
- cada registrador guarda no máx. **32 bits**; o token tem **128** → `128/32 = 4`
- e cada registrador só pode ser acessado **uma vez por pacote** ✔️

**2. Por que `if`s aninhados, e não `&&`?**
- `a && b && c && d` fica **"complexo demais"** para um estágio do pipeline
- o compilador `p4c` recusa → quebramos em `if`s aninhados
- mesmo resultado lógico, mas **compila**

---

<!-- _class: lead -->

## A mudança essencial

**Antes** (esqueleto): `forward.apply()` era a **1ª** linha → roteava tudo.

**Depois**: `forward.apply()` é a **última** → só após validar o token.

> ## "Primeiro prove quem você é, depois eu te roteio."

---

## O teste (`test_tunnel.py` + Scapy)

```python
# [1] grava o token            → 0x9000  → nada sai
sendp(Ether(type=0x9000)/SecretHeader(token=MEU_TOKEN))

# [2] mensagem token ERRADO    → 0x9001  → DROPADO
sendp(Ether(type=0x9001)/SecretHeader(token=TOKEN_ERRADO))

# [3] mensagem token CERTO     → 0x9001  → SAI pela veth8
sendp(Ether(type=0x9001)/SecretHeader(token=MEU_TOKEN))
```

> **Scapy** monta pacotes byte a byte em Python.
> Observamos a saída com `tcpdump -i veth8`.

---

## Demonstração ao vivo

**Terminal 1** (observar a Porta 2):
```bash
sudo tcpdump -i veth8 -e
```
**Terminal 2** (injetar os pacotes):
```bash
sudo python3 test_tunnel.py
```

| Passo | Esperado |
|-------|----------|
| [1] gravar (0x9000) | nada aparece |
| [2] token errado | nada aparece (drop) |
| [3] token certo | **aparece na veth8** ✅ |

---

## Requisitos atendidos ✅

| O enunciado pede | Entregue |
|------------------|----------|
| Token de **16 bytes** | ✅ `bit<128>` |
| Token na **SRAM** | ✅ 4 registradores |
| **Gravar** o token | ✅ pacote `0x9000` |
| **Validar** e filtrar | ✅ pacote `0x9001` |
| `headers/parser/secret.p4` + testes | ✅ todos |

---

## Análise crítica (evoluções possíveis)

Tudo dentro do escopo — mas dá para evoluir:

- O cabeçalho `secret` **viaja junto** até o destino
  → poderíamos removê-lo (`setInvalid()`) no sucesso.
- **Default-deny**: tráfego comum não passa
  → escolha de política, não bug.
- Token em **texto puro** → sniffável; o real usaria criptografia.

> Levantar isso mostra que entendemos o trabalho a fundo.

---

<!-- _class: lead -->
<!-- _paginate: false -->

# Obrigado! 🙏

**Resumo:** 3 fluxos (gravar · validar · dropar)
+ 2 truques de hardware (4 registradores · `if`s aninhados)
+ a regra de ouro: **validar antes de rotear**.

### Perguntas?
