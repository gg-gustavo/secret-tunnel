# 2. Anatomia de um programa P4 (com tradução para quem sabe C)

> Objetivo: apresentar **cada construção da linguagem P4** que aparece no
> trabalho, sempre com um paralelo em C. Ao final, você vai reconhecer todas as
> peças quando abrir os arquivos no doc 3.

A "tabela de tradução" rápida (volte aqui sempre que precisar):

| Construção P4 | "É tipo… em C" | Resumo |
|---------------|----------------|--------|
| `bit<N>` | inteiro sem sinal de N bits | tipo de tamanho exato |
| `typedef bit<48> mac_addr_t;` | `typedef` | apelido de tipo |
| `header` | `struct` com bitfields + um bit de "válido?" | molde de um cabeçalho |
| `struct` | `struct` | agrupa campos/headers |
| `parser` / `state` | máquina de estados (switch + goto) | lê bytes → preenche headers |
| `pkt.extract(h)` | `memcpy` do buffer + avança cursor | lê um header do pacote |
| `transition select(x)` | `switch (x)` | escolhe o próximo estado |
| `control { apply { … } }` | uma **função** chamada por pacote | onde mora a lógica |
| `action` | função (corpo executado no acerto da tabela) | o "faça isso" |
| `table` | tabela de consulta configurável (dispatch) | "se a chave casar, rode a ação" |
| `Register<…>` | array `static` que sobrevive entre chamadas | memória persistente (SRAM) |
| `meta` (metadata) | variáveis locais do "contexto" do pacote | rascunho, zera a cada pacote |
| `intrinsic metadata` | registradores especiais do hardware | conversa com o chip (porta, drop…) |
| `pkt.emit(h)` | serializa struct → bytes | escreve o header de volta no pacote |

Agora, uma a uma.

---

## 2.1 Tipos: `bit<N>` e `typedef`

Em P4 não existe `int` ou `char`. Você diz **exatamente** quantos bits o campo
tem, porque o hardware mexe bit a bit.

```p4
typedef bit<48> mac_addr_t;     // um endereço MAC tem exatamente 48 bits
typedef bit<16> ether_type_t;   // o EtherType tem 16 bits
```

- `bit<48>` = inteiro **sem sinal** de 48 bits.
- `typedef` funciona igualzinho ao de C: cria um apelido legível.

No trabalho, o token é `bit<128>` — um número de 128 bits (16 bytes). Em C não
existe um tipo nativo de 128 bits; aqui é natural.

---

## 2.2 `header`: o molde de um cabeçalho

```p4
header ethernet_h {
    mac_addr_t dst_addr;   // 48 bits
    mac_addr_t src_addr;   // 48 bits
    bit<16>    ether_type; // 16 bits
}
```

Um `header` é **quase** uma `struct` de C com campos de tamanho exato (como
bitfields). Mas tem uma diferença importantíssima:

> Todo header carrega, escondido, um **bit de validade** ("estou presente neste
> pacote ou não?"). Você o controla indiretamente: quando o parser faz
> `extract`, o header fica **válido**; o deparser só escreve (`emit`) os
> headers **válidos**.

Em C seria como ter, junto da `struct`, um booleano `bool present;` que diz se
aquela struct realmente faz parte deste pacote. Isso é central no trabalho: o
header `secret` só é válido nos pacotes `0x9000`/`0x9001`; nos demais ele "não
existe".

O trabalho adiciona um header novo:

```p4
header secret_h {
    bit<128> token;   // os 16 bytes do segredo
}
```

---

## 2.3 `struct`: juntando tudo

Há duas structs "globais" que circulam pela esteira inteira:

```p4
struct header_t {          // todos os cabeçalhos possíveis do pacote
    ethernet_h ethernet;
    secret_h   secret;     // (adicionado no trabalho)
}

struct metadata_t {        // rascunho que acompanha o pacote
    bit<32> aux1;  bit<32> aux2;
    bit<32> aux3;  bit<32> aux4;
    bit<128> aux5;
}
```

- `header_t hdr` → o pacote "interpretado". É o que você lê e modifica.
- `metadata_t meta` → **variáveis de rascunho** que vivem só durante a
  passagem **deste** pacote pela esteira. Zeram para o próximo pacote.

> Analogia C: `meta` são como **variáveis locais** de uma função que roda uma
> vez por pacote. `hdr` é o **parâmetro** (o pacote) que essa função recebe e
> pode alterar.

No trabalho, `meta.aux1..aux4` servem para **guardar temporariamente** os 4
pedaços do token lidos da memória, para depois comparar.

---

## 2.4 `parser`: a máquina de estados que lê o pacote

O parser pega os **bytes crus** que chegaram pela porta e os encaixa nos
headers. Ele é escrito como uma **máquina de estados**:

```p4
state start {
    /* ... prepara ... */
    transition parse_ethernet;        // vá para o próximo estado
}

state parse_ethernet {
    pkt.extract(hdr.ethernet);        // lê 14 bytes → preenche hdr.ethernet
    transition select(hdr.ethernet.ether_type) {   // olhe o EtherType e decida
        0x9000: parse_secret;         // se for 0x9000, vá ler o token
        0x9001: parse_secret;         // idem para 0x9001
        default: accept;              // senão, termine aqui
    }
}

state parse_secret {
    pkt.extract(hdr.secret);          // lê 16 bytes → preenche hdr.secret
    transition accept;                // pacote totalmente lido
}
```

Traduzindo para C, é exatamente um **autômato com `goto`**:

```c
start:        goto parse_ethernet;
parse_ethernet:
    memcpy(&hdr.ethernet, cursor, 14); cursor += 14;
    switch (hdr.ethernet.ether_type) {
        case 0x9000: goto parse_secret;
        case 0x9001: goto parse_secret;
        default:     goto accept;
    }
parse_secret:
    memcpy(&hdr.secret, cursor, 16); cursor += 16;
    goto accept;
accept: ;
```

Pontos-chave:

- **`pkt.extract(h)`**: copia os próximos bytes do pacote para o header `h`,
  marca `h` como **válido** e **avança o cursor**. É um "ler e consumir".
- **`transition select(x) { … }`**: é o `switch (x)` do P4 — escolhe o próximo
  estado conforme o valor de `x`. (`default` é o `default:` do switch.)
- **`accept`** / **`reject`**: estados finais (deu certo / falhou).

> 💡 Por isso o parser do trabalho olha o `ether_type`: se for um dos nossos
> tipos especiais, ele **continua lendo** mais 16 bytes (o token); senão, para.

---

## 2.5 `control` e `apply`: a lógica por pacote

```p4
control SwitchIngress( /* parâmetros: hdr, meta, e metadatas do hardware */ ) {
    /* aqui dentro você declara tabelas, ações e registradores */
    apply {
        /* este bloco roda UMA VEZ para cada pacote */
    }
}
```

- Um `control` é como um **arquivo/módulo** que agrupa tabelas, ações e a
  lógica.
- O bloco **`apply { … }`** é o **corpo da função** que roda por pacote. Dentro
  dele você pode usar `if`/`else` normais (como em C) e **chamar tabelas**.

Aqui, sim, o P4 se parece com C: tem `if`, `else`, comparações, atribuições.
A diferença é o que você **pode** fazer (sem loops; cuidado com registradores).

---

## 2.6 `action` e `table`: o coração do "match-action"

Esta dupla é a marca registrada do P4. Não há equivalente direto em C, então
preste atenção.

### `action` = a "função-resposta"

```p4
action hit(PortId_t port) {
    ig_tm_md.ucast_egress_port = port;   // mande o pacote para esta porta
}
action miss(bit<3> drop) {
    ig_dprsr_md.drop_ctl = drop;         // descarte o pacote
}
```

Uma `action` é um corpo de código (como uma função pequena) que será executado
**quando uma tabela encontrar uma correspondência**. Os parâmetros da action
(ex.: `port`) podem ser preenchidos pelo **plano de controle**.

### `table` = a tabela de consulta configurável

```p4
table forward {
    key = {
        hdr.ethernet.dst_addr : exact;   // chave: o MAC de destino (casamento exato)
    }
    actions = {
        hit;                              // ações possíveis
        @defaultonly miss;
    }
    const default_action = miss(0x1);     // se nada casar: dropar
    size = 1024;                          // capacidade da tabela
}
```

Como funciona, mentalmente:

1. O switch pega a **chave** (`hdr.ethernet.dst_addr`).
2. Procura essa chave na tabela `forward`.
3. **Achou** → executa a ação associada àquela linha (ex.: `hit(porta=2)`).
4. **Não achou** → executa a `default_action` (aqui, `miss` = dropar).

> Em C, é como um `switch` gigante OU um `hash_map<chave, função+args>` — mas
> com uma diferença essencial: **quem preenche as linhas da tabela é o plano de
> controle**, em tempo de execução, não o programador P4.

#### Quem preenche a tabela `forward`?

O `setup.py` (control plane), com esta linha:

```python
p4.SwitchIngress.forward.add_with_hit(dst_addr=switch_port.mac,
                                      port=get_device_port(switch_port.port_name))
```

Ou seja: para cada porta configurada, ele insere uma linha "MAC tal → ação
`hit` com a porta tal". É assim que o switch sabe que o MAC
`00:00:00:00:00:02` deve sair pela Porta 2. **Você não precisa mexer nisso** —
já vem pronto.

> 📌 No trabalho, a tabela `forward` é o "roteamento normal". A sacada do colega
> foi: **só chamar `forward.apply()` se o token for válido.** Pacote sem token
> certo nunca chega ao roteamento.

---

## 2.7 `Register`: a memória que sobrevive entre pacotes

Variáveis normais (`meta`) **zeram** a cada pacote. Mas o trabalho precisa
**lembrar** o token entre um pacote (o que grava) e outro (o que valida). Para
isso existem os **registradores** — pedaços de **SRAM** dentro do chip que
persistem.

```p4
Register<bit<32>, bit<1>>(1) secret_reg1;
//        │         │      └── quantas posições tem o array: 1
//        │         └───────── tipo do índice: bit<1> (endereça posição 0 ou 1)
//        └─────────────────── tipo do valor guardado: bit<32>
```

> Analogia C: é um **`static`** array que mantém o valor entre chamadas:
> ```c
> static uint32_t secret_reg1[1];   // sobrevive entre "execuções por pacote"
> ```

Como ler e escrever (API que o **professor** indicou no enunciado):

```p4
secret_reg1.write(0, valor);   // grava 'valor' na posição 0
x = secret_reg1.read(0);       // lê a posição 0
```

### Por que 4 registradores, e não 1?

Lembra das regras duras (doc 1)? Aqui elas batem à porta:

1. **Cada registrador guarda no máximo 32 bits** — mas o token tem 128. Logo,
   precisamos de `128 / 32 = 4` registradores.
2. **Um registrador só pode ser acessado uma vez por pacote.** No fluxo de
   gravação só fazemos `write`; no de validação só fazemos `read`. Nunca os
   dois no mesmo pacote. ✔️

O próprio comentário do enunciado avisa:
*"o mesmo registrador não pode ser acessado mais de uma vez por pacote, e
armazenam valores de no máximo 32 bits, utilize múltiplos registradores."*

O colega seguiu a dica à risca: 4 registradores de 32 bits = 128 bits de token.

---

## 2.8 "Fatiar" bits: `token[31:0]`

Como o token é de 128 bits mas os registradores são de 32, é preciso **cortar**
o token em 4 pedaços. P4 faz isso com a notação `[alto:baixo]`:

```p4
hdr.secret.token[31:0]     // bits 0 a 31   (1º pedaço)
hdr.secret.token[63:32]    // bits 32 a 63  (2º pedaço)
hdr.secret.token[95:64]    // bits 64 a 95  (3º pedaço)
hdr.secret.token[127:96]   // bits 96 a 127 (4º pedaço)
```

> Em C você faria com máscara e deslocamento:
> `(uint32_t)((token >> 32) & 0xFFFFFFFF)`. Em P4 a sintaxe `[63:32]` faz isso
> de forma direta e legível.

---

## 2.9 As "metadatas intrínsecas": conversando com o hardware

Você verá parâmetros estranhos nos controles, como `ig_dprsr_md`, `ig_tm_md`.
São structs **fornecidas pelo Tofino** ("intrinsic metadata") que servem para
você **dar ordens ao chip** ou **ler informações dele**. As duas que importam:

| Campo | Significado | Usado para |
|-------|-------------|------------|
| `ig_tm_md.ucast_egress_port` | "porta de saída unicast" | dizer para qual porta mandar o pacote |
| `ig_dprsr_md.drop_ctl` | "controle de descarte" | pôr `1` para **dropar** o pacote |

> Analogia C: são como **registradores mapeados em memória** de um periférico.
> Você escreve num campo e o hardware "obedece" — escrever `1` em
> `drop_ctl` é como acionar um sinal de "joga esse pacote fora".

Por isso, no trabalho, **dropar** um pacote é simplesmente:

```p4
ig_dprsr_md.drop_ctl = 1;
```

E **rotear** é deixar a tabela `forward` setar `ig_tm_md.ucast_egress_port`.

---

## 2.10 `deparser` e `emit`: remontar o pacote para a saída

Depois que a lógica decidiu tudo, o **deparser** transforma os headers de volta
em bytes:

```p4
control SwitchIngressDeparser(...) {
    apply {
        pkt.emit(hdr);   // escreve de volta TODOS os headers válidos, em ordem
    }
}
```

- `pkt.emit(hdr)` é o **inverso** de `extract`: serializa os headers de volta
  no fio. **Só emite os headers válidos** (lembra do bit de validade, 2.2).
- Se um header foi marcado inválido, ele simplesmente **não sai** no pacote
  (é assim que se "remove" um cabeçalho — não é o caso neste trabalho, mas é um
  conceito comum).

> Analogia C: `extract` é o `fread`/`memcpy` que lê a struct do buffer; `emit`
> é o `fwrite`/`memcpy` que escreve a struct de volta no buffer de saída.

---

## 2.11 Montando o pipeline: `Pipeline(...)` e `Switch(...) main`

No fim do `secret.p4`:

```p4
Pipeline(
    SwitchIngressParser(),    // 1. ler na entrada
    SwitchIngress(),          // 2. decidir na entrada
    SwitchIngressDeparser(),  // 3. remontar na entrada
    SwitchEgressParser(),     // 4. ler na saída
    SwitchEgress(),           // 5. (vazio aqui)
    SwitchEgressDeparser()    // 6. remontar na saída
) pipe;

Switch(pipe) main;
```

Isto **conecta as peças na ordem da esteira** (doc 1.3) e declara o programa
final. `Switch(pipe) main;` é o ponto de entrada — o equivalente conceitual do
`int main()` em C: é por aqui que o Tofino sabe "este é o programa para rodar".

---

## ✅ O que levar deste documento

- Um programa P4 é feito de **headers** (moldes), um **parser** (máquina de
  estados que lê), **controls** com **tabelas + ações** (a lógica
  match-action), **registradores** (memória persistente) e um **deparser**
  (remonta a saída).
- **Tabela + ação** é o coração do P4: a tabela casa uma chave e dispara uma
  ação; **o plano de controle preenche as linhas**.
- **Registradores** são a única memória que **sobrevive entre pacotes** — daí
  serem usados para guardar o token. As regras de hardware (32 bits, 1 acesso)
  forçam o uso de **4 registradores**.
- Você fala com o hardware via **metadatas intrínsecas** (`drop_ctl`,
  `ucast_egress_port`).

➡️ Próximo: [03-o-trabalho-passo-a-passo.md](03-o-trabalho-passo-a-passo.md) —
agora juntamos tudo e lemos o trabalho real, comparando o que o professor deu
com o que o colega implementou.
