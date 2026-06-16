# 3. O trabalho, passo a passo: o que veio do professor × o que o colega fez

> Objetivo: ler o trabalho real comparando os **dois commits**. Para cada
> arquivo, mostramos o **antes** (esqueleto do professor), o **depois**
> (implementação) e **por que** cada mudança foi feita. Este é o documento que
> você vai consultar mais durante a apresentação.

## 3.0 Os dois commits

| Commit | Autor | O que é |
|--------|-------|---------|
| `2426092` — *"initial setup from main repository"* | Professor | Esqueleto: tudo compila, mas a lógica do túnel está **vazia**, com dicas em comentários. |
| `80fee1c` — *"implementar secret header e lógica de túnel"* | Colega | A implementação do túnel secreto nos 3 arquivos + o script de teste. |

O professor entregou um "preencha as lacunas": a estrutura do switch (parsers
do Tofino, tabela de roteamento, um registrador de exemplo) já estava pronta, e
nos comentários ele indicava **onde** e **como** completar. O trabalho do colega
foi preencher essas lacunas.

A ideia geral, em três fluxos (decore isto — é a espinha dorsal):

| Pacote | EtherType | O que o switch faz |
|--------|-----------|--------------------|
| **Gravar token** | `0x9000` | Lê o token do pacote e **escreve** nos 4 registradores. Depois **dropa** o próprio pacote (é só configuração). |
| **Mensagem** | `0x9001` | **Lê** os 4 registradores, compara com o token do pacote. Igual → **roteia**. Diferente → **dropa**. |
| **Qualquer outro** | — | **Dropa** (default-deny: o que não é do túnel não passa). |

---

## 3.1 `headers.p4` — declarar o cabeçalho secreto

### O que mudou

O professor já tinha o header `ethernet_h` e a struct `header_t`. O colega
adicionou o header `secret_h` e o incluiu na struct:

```p4
/* ADICIONADO pelo colega */
header secret_h {
    bit<128> token;        // 16 bytes = 128 bits, exatamente como o enunciado pede
}

struct header_t {
    ethernet_h ethernet;
    secret_h   secret;     // ADICIONADO: agora o pacote pode ter um cabeçalho "secret"
}
```

### Por que

- O enunciado exige um token de **16 bytes** → `bit<128>`. Está correto.
- Declarar um `header` novo é o **primeiro passo** sempre que se cria um
  "protocolo" próprio: você define o **molde** dos bytes que virão no pacote.
- Incluí-lo em `header_t` é o que permite o parser/lógica/deparser
  enxergarem esse cabeçalho.

> A struct `metadata_t` (aux1..aux5) **já existia** no esqueleto do professor —
> o colega só passou a usá-la. Não foi alterada.

📎 Veja o arquivo comentado: [src/secret/headers.p4](../src/secret/headers.p4)

---

## 3.2 `parser.p4` — ensinar o switch a ler o token

### O que mudou (Ingress)

O esqueleto do professor parava de ler logo após o Ethernet, com a dica
`/* DICA: utilizar transition select */`. O colega completou:

```p4
state parse_ethernet {
    meta = {0, 0, 0, 0, 0};            // zera os metadados (já existia no esqueleto)
    pkt.extract(hdr.ethernet);         // lê o cabeçalho Ethernet (já existia)

    /* ADICIONADO: decide o próximo passo conforme o EtherType */
    transition select(hdr.ethernet.ether_type) {
        0x9000: parse_secret;          // pacote de gravação → ler o token
        0x9001: parse_secret;          // pacote de mensagem → ler o token
        default: accept;               // qualquer outra coisa → não tem token, pare
    }
}

/* ADICIONADO: estado que lê os 16 bytes do token */
state parse_secret {
    pkt.extract(hdr.secret);           // preenche hdr.secret e o marca como "válido"
    transition accept;
}
```

### Por que

- O `select` sobre o `ether_type` é o ponto onde o switch decide: *"este
  pacote é do meu protocolo secreto?"* Se for (`0x9000`/`0x9001`), ele
  **continua lendo** mais 16 bytes; senão, para por ali.
- Só depois do `extract(hdr.secret)` é que `hdr.secret.token` passa a ter um
  valor utilizável na lógica do `secret.p4`. Sem este estado, o token seria
  invisível para o resto do programa.

### O espelho no Egress

O colega **repetiu** a mesma lógica no `SwitchEgressParser`:

```p4
/* Espelhamos a lógica do Ingress para evitar falhas no pipeline de saída */
transition select(hdr.ethernet.ether_type) {
    0x9000: parse_secret;
    0x9001: parse_secret;
    default: accept;
}
```

**Por quê?** Lembre da esteira (doc 1.3): depois do Traffic Manager, o pacote
**entra de novo num parser**, agora o de saída (egress). Um pacote válido que
está sendo roteado ainda carrega o cabeçalho `secret`. Para que o lado de
saída enxergue esse cabeçalho de forma coerente e o remonte corretamente, o
egress precisa saber lê-lo também. Por isso o colega "espelhou" o parser. É uma
escolha **defensiva e segura** — mantém a entrada e a saída com a mesma visão
do pacote.

📎 Veja o arquivo comentado: [src/secret/parser.p4](../src/secret/parser.p4)

---

## 3.3 `secret.p4` — o cérebro: gravar, validar, rotear, dropar

Este é o arquivo central. Vamos por partes.

### 3.3.1 Os registradores: de 1 para 4

**Antes (professor)** — um único registrador de exemplo:

```p4
Register<bit<32>, bit<1>> (1) secret_values;
```

**Depois (colega)** — quatro registradores de 32 bits:

```p4
Register<bit<32>, bit<1>>(1) secret_reg1;
Register<bit<32>, bit<1>>(1) secret_reg2;
Register<bit<32>, bit<1>>(1) secret_reg3;
Register<bit<32>, bit<1>>(1) secret_reg4;
```

**Por quê?** (já adiantado nos docs 1.4 e 2.7): o token tem 128 bits, mas cada
registrador guarda no máximo 32 → `128/32 = 4`. E como cada registrador só pode
ser acessado uma vez por pacote, dividir em quatro permite gravar/ler todos os
pedaços dentro de um mesmo pacote, **sem violar a regra**. Foi exatamente o que
o enunciado sugeriu nas dicas.

### 3.3.2 O bloco `apply`: a lógica completa

**Antes (professor)** — apenas roteava sempre e tinha as dicas em comentário:

```p4
apply {
    forward.apply();          // roteava TODO pacote, sem filtro nenhum
    /* dicas de como ler/escrever registrador e dropar... */
}
```

**Depois (colega)** — a lógica do túnel, com os três fluxos:

```p4
apply {
    if (hdr.ethernet.ether_type == 0x9000) {
        /* FLUXO A — GRAVAÇÃO: copia o token do pacote para a SRAM */
        secret_reg1.write((bit<1>)0, hdr.secret.token[31:0]);
        secret_reg2.write((bit<1>)0, hdr.secret.token[63:32]);
        secret_reg3.write((bit<1>)0, hdr.secret.token[95:64]);
        secret_reg4.write((bit<1>)0, hdr.secret.token[127:96]);

        ig_dprsr_md.drop_ctl = 1;          // pacote de config não deve seguir adiante
    }
    else if (hdr.ethernet.ether_type == 0x9001) {
        /* FLUXO B — VALIDAÇÃO: lê a SRAM e compara com o token do pacote */
        meta.aux1 = secret_reg1.read((bit<1>)0);
        meta.aux2 = secret_reg2.read((bit<1>)0);
        meta.aux3 = secret_reg3.read((bit<1>)0);
        meta.aux4 = secret_reg4.read((bit<1>)0);

        /* comparação em ifs aninhados (ver 3.3.3) */
        if (hdr.secret.token[31:0] == meta.aux1) {
            if (hdr.secret.token[63:32] == meta.aux2) {
                if (hdr.secret.token[95:64] == meta.aux3) {
                    if (hdr.secret.token[127:96] == meta.aux4) {
                        forward.apply();   // TUDO casou → roteia normalmente
                    } else { ig_dprsr_md.drop_ctl = 1; }
                } else { ig_dprsr_md.drop_ctl = 1; }
            } else { ig_dprsr_md.drop_ctl = 1; }
        } else { ig_dprsr_md.drop_ctl = 1; }
    }
    else {
        /* FLUXO C — qualquer outro pacote é descartado (default-deny) */
        ig_dprsr_md.drop_ctl = 1;
    }
}
```

Vamos destrinchar cada fluxo:

#### Fluxo A — Gravação (`0x9000`)

1. O token do pacote (128 bits) é **fatiado** em 4 pedaços de 32 bits e cada um
   é **escrito** num registrador. A partir daí, o switch "lembra" o token.
2. `ig_dprsr_md.drop_ctl = 1` **descarta** o pacote de configuração — ele
   cumpriu seu papel (gravar) e não deve ir para nenhum destino. Isso bate
   exatamente com o primeiro desenho do enunciado (o pacote que grava o token
   é barrado com um `X` antes do destino).

#### Fluxo B — Validação (`0x9001`)

1. **Lê** os 4 registradores para `meta.aux1..aux4` (rascunho). Repare:
   `read` só é chamado **uma vez por registrador** — regra respeitada.
2. Compara, pedaço a pedaço, o token do **pacote** com o token **guardado**.
3. Se **todos os 4** pedaços batem → `forward.apply()`: o pacote entra na
   tabela de roteamento e é mandado para a porta certa. **É a única forma de um
   pacote chegar ao roteamento.**
4. Se **qualquer** pedaço difere → `drop_ctl = 1` (descartado).

#### Fluxo C — Qualquer outro EtherType

Descartado. O switch vira um "túnel secreto" puro: o que não fala o protocolo
secreto não passa. (Veja a discussão sobre isso no doc 4.)

### 3.3.3 Por que os `if`s aninhados em vez de `&&`?

A forma "natural" seria:

```p4
if (a == r1 && b == r2 && c == r3 && d == r4) { forward.apply(); }
```

Mas o próprio comentário do colega explica:
*"Isso evita o erro de 'condition too complex' do compilador."*

Lembra da regra dura do doc 1.4? Cada estágio do PISA tem hardware finito para
avaliar condições. Uma condição com quatro comparações de 32 bits unidas por
`&&` pode **estourar** a capacidade de um único estágio, e o compilador `p4c`
recusa. Ao **aninhar** os `if`s, cada comparação é avaliada "em camadas",
cabendo no hardware. O resultado lógico é idêntico (só passa quem acerta os 4),
mas agora **compila**. Esse é um padrão clássico de programação P4 — e um ótimo
ponto para mostrar que você entende as limitações do hardware.

### 3.3.4 A ordem importa: validar ANTES de rotear

Repare na mudança mais sutil e mais importante:

- **Antes:** `forward.apply()` era a **primeira** coisa do `apply` — todo
  pacote era roteado, sem filtro.
- **Depois:** `forward.apply()` só é chamado **lá no fundo**, dentro do quarto
  `if`, depois de provar que o token está 100% correto.

> 🔑 Esta inversão é a essência do trabalho: **"primeiro prove quem você é,
> depois eu te roteio"**. É o que transforma um switch comum num porteiro com
> senha. É o ponto que você deve enfatizar na apresentação.

### 3.3.5 O Egress continua vazio

```p4
control SwitchEgress(...) {
    apply {}
}
```

Não há nada a fazer na saída além de remontar o pacote (que o deparser já faz).
Toda a decisão acontece no Ingress. Está correto e é o esperado para este
trabalho.

📎 Veja o arquivo comentado: [src/secret/secret.p4](../src/secret/secret.p4)

---

## 3.4 `test_tunnel.py` — provar que funciona (Scapy)

Este arquivo é **novo** (não existia no commit do professor). Ele usa a
biblioteca **Scapy** (Python) para fabricar e enviar pacotes — o jeito
recomendado pelo próprio enunciado.

```python
# 1. Ensina o Scapy o formato do nosso cabeçalho secreto (token de 128 bits)
class SecretHeader(Packet):
    fields_desc = [ BitField("token", 0, 128) ]

# 2. Liga o cabeçalho secreto ao Ethernet quando o EtherType for 0x9000/0x9001
bind_layers(Ether, SecretHeader, type=0x9000)
bind_layers(Ether, SecretHeader, type=0x9001)

MEU_TOKEN    = 0xAAAA...AAAA   # token "certo"
TOKEN_ERRADO = 0xBBBB...BBBB   # token "errado"

# [1] grava o token (0x9000)
sendp(Ether(..., type=0x9000)/SecretHeader(token=MEU_TOKEN), iface="veth0")

# [2] mensagem com token ERRADO (0x9001) → deve ser dropada
sendp(Ether(..., type=0x9001)/SecretHeader(token=TOKEN_ERRADO), iface="veth0")

# [3] mensagem com token CERTO (0x9001) → deve passar para a Porta 2 (veth8)
sendp(Ether(..., type=0x9001)/SecretHeader(token=MEU_TOKEN), iface="veth0")
```

A correspondência com a lógica do `secret.p4` é direta:

| Passo do teste | EtherType | Fluxo acionado no switch | Resultado esperado |
|----------------|-----------|--------------------------|--------------------|
| [1] gravar | `0x9000` | Fluxo A (grava + dropa) | Nada sai (config) |
| [2] errado | `0x9001` | Fluxo B (não casa) | **Dropado** |
| [3] certo  | `0x9001` | Fluxo B (casa) | **Sai pela veth8** |

O `time.sleep(1)` entre os envios garante que o token já esteja gravado antes
de testar a validação. Como os registradores **persistem** (doc 2.7), o valor
gravado no passo [1] continua lá nos passos [2] e [3].

> Para **observar** o resultado, rode num outro terminal:
> `sudo tcpdump -i veth8` — só o pacote do passo **[3]** deve aparecer.

📎 Veja o arquivo comentado: [test_tunnel.py](../test_tunnel.py)

---

## 3.5 Detalhes de fechamento (não-funcionais)

No diff aparecem algumas mudanças que **não alteram o comportamento**, só vale
saber explicar se perguntarem:

- A indentação do `#define _HEADERS_` mudou e alguns arquivos perderam a
  quebra de linha final (`\ No newline at end of file`). São cosméticos.
- Vários comentários do esqueleto foram reescritos em português pelo colega
  (ex.: `/* Forward */` virou `/* Ações de Encaminhamento */`). Sem efeito no
  binário.

Nenhuma dessas mudanças afeta a lógica nem a compilação.

---

## ✅ O que levar deste documento

- O professor deu o **esqueleto**; o colega preencheu **3 lacunas**: declarar o
  header (`headers.p4`), ler o token (`parser.p4`) e implementar
  gravar/validar/rotear/dropar (`secret.p4`), além de criar o **teste**.
- A lógica tem **3 fluxos**: gravar (`0x9000`), validar (`0x9001`) e
  descartar (o resto).
- Os dois "truques" — **4 registradores** e **`if`s aninhados** — são respostas
  diretas às limitações do hardware PISA.
- A mudança conceitual central: **validar antes de rotear**.

➡️ Próximo: [04-requisitos-atendidos.md](04-requisitos-atendidos.md) — a prova
item a item de que o enunciado foi cumprido.
