# 1. Fundamentos: P4, switches programáveis, PISA e Tofino

> Objetivo deste documento: te dar a "visão de cima" antes de ler qualquer
> código. Quando você entender **onde** o P4 roda e **por que** ele é tão
> restrito, o código vai fazer todo sentido.

---

## 1.1 O problema que o P4 resolve

Um **switch** é o aparelho que recebe pacotes de rede em uma porta e decide
para qual porta enviá-los. Tradicionalmente, esse comportamento vinha
"de fábrica": o fabricante gravava no chip (ASIC) o que era um pacote
Ethernet, o que era IP, etc. Se você quisesse um protocolo novo ou uma regra
diferente, **azar** — tinha que esperar a próxima geração de hardware.

**P4** muda isso. P4 = *"Programming Protocol-independent Packet Processors"*
(Programação de Processadores de Pacotes Independentes de Protocolo).

> Em uma frase: **P4 é a linguagem com que você programa o que o switch faz
> com cada pacote.** Você descreve quais cabeçalhos existem, como lê-los, e
> que decisão tomar — e o chip passa a obedecer.

### Analogia com C

- Em C, você programa o que a **CPU** faz com dados na memória.
- Em P4, você programa o que o **switch** faz com pacotes que passam por ele.

A diferença crucial: a CPU é genérica e executa qualquer algoritmo. O switch é
um hardware especializado em uma coisa só — processar pacotes a **velocidade
de linha** (line rate), ou seja, bilhões de bits por segundo, sem nunca
atrasar. Isso impõe **regras duras** sobre o que o P4 permite (veremos em 1.4).

---

## 1.2 Plano de Dados vs. Plano de Controle

Esta é a distinção mais importante para entender o trabalho. Decore:

| | **Plano de Dados** (Data Plane) | **Plano de Controle** (Control Plane) |
|--|--------------------------------|----------------------------------------|
| O que é | O caminho por onde **cada pacote** passa | O "cérebro administrativo" que configura o switch |
| Velocidade | Rapidíssimo (bilhões de pacotes/s) | Lento (roda numa CPU comum) |
| Escrito em | **P4** | Python, C++, gRPC… (aqui: `setup.py`) |
| Frequência | Executa **por pacote** | Executa "de vez em quando" (na inicialização, ou ao mudar uma regra) |
| Exemplo no trabalho | "este pacote tem o token certo? então mande para a porta 2" | "preencher a tabela de roteamento dizendo qual MAC vai para qual porta" |

> 🔑 O enunciado diz **"Não precisa mexer no control plane"**. Ou seja: todo o
> trabalho de vocês está no **plano de dados** (os arquivos `.p4`). O
> `setup.py` já vem pronto do professor.

Pense assim: o **plano de controle** é o gerente que, uma vez, prega na parede
as regras ("MAC X → porta 1"). O **plano de dados** é o funcionário que, para
cada cliente que chega, lê as regras da parede e age na hora. O P4 programa o
funcionário; o `setup.py` é o gerente pregando as regras.

---

## 1.3 PISA: a "linha de montagem" dentro do switch

PISA = *Protocol-Independent Switch Architecture* (Arquitetura de Switch
Independente de Protocolo). É o **modelo de hardware** que o chip Tofino
implementa. Pense numa **fábrica com uma esteira**: o pacote entra por uma
ponta, passa por estações fixas em sequência, e sai pela outra. Cada estação
faz uma parte do trabalho e **passa adiante** — nunca volta.

```
            INGRESS (entrada)                       EGRESS (saída)
   ┌──────────────────────────────┐   ┌────┐   ┌──────────────────────────────┐
 → │ Parser → Match-Action stages │ → │ TM │ → │ Parser → Match-Action → Depar│ →
   │              → Deparser       │   │    │   │                               │
   └──────────────────────────────┘   └────┘   └──────────────────────────────┘
      "ler e decidir na entrada"      fila/    "ler e ajustar na saída"
                                      cópia
```

As estações da esteira, em ordem:

1. **Parser** ("leitor"): olha os bytes crus do pacote e os organiza em
   cabeçalhos que você definiu (Ethernet, IP, e aqui o nosso `secret`). É uma
   **máquina de estados** (veja o doc 2).
2. **Match-Action Pipeline** ("decisor"): uma sequência de estágios. Em cada
   estágio, o switch **procura (match)** um valor numa tabela e **executa
   (action)** o que estiver associado. É aqui que mora a lógica do `apply`.
3. **Traffic Manager (TM)**: o meio de campo. Enfileira o pacote, pode
   duplicá-lo (multicast), e o entrega ao lado de saída. É **fixo**, não
   programável em P4.
4. **Deparser** ("remontador"): pega os cabeçalhos (possivelmente modificados)
   e os **escreve de volta** como bytes, montando o pacote que sai pela porta.

> Note que há **dois lados**: *Ingress* (entrada) e *Egress* (saída), cada um
> com seu próprio parser, pipeline e deparser. No nosso trabalho, quase toda a
> lógica está no **Ingress**; o Egress só "espelha" o parser para a saída sair
> coerente.

### Por que uma esteira, e não um "loop como em C"?

Porque é assim que se atinge velocidade de linha. Numa esteira, cada pacote
gasta um tempo **fixo e previsível** em cada estação. Não há "while", não há
"espere aqui" — o pacote sempre avança. Isso garante que o switch nunca
engasgue, mas é também a **origem de todas as limitações** do P4.

---

## 1.4 As regras duras do P4 (e de onde vêm as "manias" do código)

Como tudo é uma esteira em hardware, o P4 **proíbe** coisas que em C são
triviais. Guarde estas, porque elas explicam decisões estranhas no código do
trabalho:

| Em C você faz… | Em P4… | Por quê |
|----------------|--------|---------|
| `while`, `for`, recursão | ❌ Proibido (sem loops de tamanho indefinido) | A esteira não volta; o tempo por pacote tem que ser fixo. |
| Alocar memória (`malloc`) | ❌ Não existe | Não há heap; a memória é fixa no chip. |
| Ler/escrever uma variável quantas vezes quiser | ⚠️ Registradores: **1 acesso por pacote** | Cada estágio tem hardware finito; ler duas vezes exigiria dois caminhos. |
| Tipos `int`, `char` (tamanho da máquina) | `bit<N>` — você diz **exatamente** quantos bits | O hardware manipula campos bit a bit. |
| Expressões booleanas gigantes (`a && b && c && d`) | ⚠️ Pode estourar a capacidade de um estágio | Cada comparação consome um pedaço do hardware do estágio. |

> 💡 **Guarde este ponto** — ele aparece literalmente no trabalho:
> 1. O token tem 128 bits, mas cada registrador guarda no máximo **32 bits** →
>    por isso o colega usou **4 registradores**.
> 2. Como não dá para encadear `a && b && c && d` num estágio só, o colega
>    quebrou a comparação em **`if`s aninhados** (um dentro do outro).
>
> Os dois "truques" do trabalho são consequências diretas dessas regras.

---

## 1.5 Tofino: o chip (e o simulador)

- **Tofino** é um chip de switch real da Intel (antiga Barefoot Networks) que
  implementa PISA e é programável em P4. Os switches de verdade usam esse chip.
- Como você não tem um switch físico na sua mesa, o trabalho usa o
  **simulador do Tofino** (`tofino-model`) rodando dentro de um container
  Docker. Ele se comporta como o chip de verdade.
- Em vez de portas físicas com cabos, o simulador usa **interfaces virtuais**
  (`veth0`, `veth8`, `veth16`). Mandar um pacote para a `veth0` é como
  plugá-lo na "Porta 1" do switch.

| Porta do switch | Interface virtual | MAC |
|-----------------|-------------------|-----|
| 1/0 | `veth0`  | `00:00:00:00:00:01` |
| 2/0 | `veth8`  | `00:00:00:00:00:02` |
| 3/0 | `veth16` | `00:00:00:00:00:03` |

### TNA — uma observação de vocabulário

Você vai ver no código `#include <tna.p4>` e nomes como
`ingress_intrinsic_metadata_t`. **TNA** = *Tofino Native Architecture*. É o
"dialeto" de P4 específico do Tofino: define os blocos exatos que o seu
programa precisa preencher (parser de ingresso, controle de ingresso, deparser
de ingresso, e os três equivalentes de egresso) e as "metadatas intrínsecas"
(veja doc 2) com que você conversa com o hardware. Pense no TNA como a
"biblioteca padrão + assinatura de funções" que o Tofino te obriga a seguir,
do mesmo jeito que `int main(int argc, char** argv)` é a assinatura que o seu
sistema operacional te obriga a seguir em C.

---

## 1.6 O ciclo de vida do trabalho (build e execução)

Para a apresentação, é bom saber **como o código vira um switch rodando**:

```
   secret.p4 ─(p4_build.sh)→  p4c (compilador P4) ─→ binário para o Tofino
                                                          │
   setup.py  ─(start_switch.sh)→ control plane + simulador Tofino sobem
                                                          │
   test_tunnel.py (Scapy) ─→ injeta pacotes na veth0 ─→ switch processa
                                                          │
   tcpdump -i veth8 ─→ você observa o que saiu
```

1. **`p4_build.sh secret`** chama o compilador `p4c`, que transforma o
   `secret.p4` (e os `#include` de headers/parser) no binário que o chip
   entende. (Análogo a `gcc` compilando seu `.c` em executável.)
2. **`start_switch.sh secret`** sobe o plano de controle (`run_switchd.sh`),
   o simulador (`run_tofino_model.sh`) e **roda o `setup.py`** para configurar
   portas e a tabela de roteamento.
3. **`test_tunnel.py`** usa o Scapy para criar os pacotes e mandá-los pela
   `veth0`.
4. **`tcpdump -i veth8`** mostra o que de fato saiu pela Porta 2 — é assim que
   você prova que o filtro funcionou.

---

## ✅ O que levar deste documento

- P4 programa o **plano de dados** de um switch; o trabalho inteiro está aí.
- O hardware é uma **esteira (PISA)**: parser → match-action → deparser, sem
  loops e sem voltar.
- As limitações (registrador de 32 bits, 1 acesso por pacote, sem `&&`
  gigante) **não são frescura** — vêm da necessidade de velocidade de linha, e
  **explicam os dois truques** do trabalho (4 registradores + `if`s aninhados).
- **Tofino** é o chip; aqui usamos o **simulador** dele com **interfaces
  virtuais** (`veth*`).

➡️ Próximo: [02-anatomia-de-um-programa-p4.md](02-anatomia-de-um-programa-p4.md)
— agora vamos abrir o capô e ver as peças de um programa P4, uma a uma.
