# 5. Roteiro de apresentação (fala, demo e perguntas do professor)

> Objetivo: te dar um **roteiro pronto** para apresentar com confiança, uma
> sugestão de **demonstração ao vivo** e um banco de **perguntas e respostas**.

---

## 5.1 Estrutura sugerida da fala (≈ 6–8 min)

Siga esta ordem. Cada bloco tem a "frase-âncora" que você pode falar quase como
está.

### Bloco 1 — O problema (30s)
> "O objetivo é transformar um switch em um filtro: ele só roteia um pacote se
> esse pacote carregar um **token secreto de 16 bytes** idêntico a um que foi
> previamente gravado na memória do próprio switch. Como não temos o hardware,
> usamos um **simulador do chip Intel Tofino**, que implementa a arquitetura
> **PISA** de switches programáveis."

### Bloco 2 — O que é P4 e onde ele roda (1–1,5 min)
> "P4 é a linguagem que programa o **plano de dados** do switch — o que ele faz
> com **cada pacote**, em velocidade de linha. Isso é diferente do **plano de
> controle**, que só configura o switch de vez em quando. O enunciado diz que
> não precisamos mexer no plano de controle; nosso trabalho está todo nos
> arquivos `.p4`."

> "O hardware funciona como uma **esteira** (PISA): o pacote entra, é **lido por
> um parser**, passa por **estágios de match-action** onde decisões são tomadas,
> e é **remontado por um deparser** na saída. Não há loops nem volta — é isso que
> garante a velocidade, e é isso que impõe as limitações que vão aparecer no
> código."

*(Se tiver slide, mostre o diagrama da esteira do doc 1.3.)*

### Bloco 3 — A arquitetura do nosso programa (1,5 min)
Mostre os 3 arquivos e o papel de cada um:
> "`headers.p4` define os **formatos** dos cabeçalhos. `parser.p4` ensina o
> switch a **ler** o token. E `secret.p4` é o **cérebro**, com a lógica de
> gravar, validar e rotear."

Apresente o header novo:
> "Criamos um cabeçalho `secret` com um campo `token` de **128 bits**, que são
> exatamente os 16 bytes pedidos."

### Bloco 4 — Os três fluxos (2 min) — **o coração da apresentação**
Desenhe/mostre a tabela dos três fluxos:

| EtherType | Significado | Ação do switch |
|-----------|-------------|----------------|
| `0x9000` | "grave este token" | escreve nos 4 registradores e dropa o pacote |
| `0x9001` | "mensagem com token" | lê os registradores, compara; igual → roteia, diferente → dropa |
| outros | tráfego comum | dropa (nega por padrão) |

> "Usamos o campo **EtherType** do Ethernet como um seletor: `0x9000` significa
> 'estou configurando o token', `0x9001` significa 'estou mandando uma mensagem
> com token'."

Explique os dois truques de hardware (mostra domínio):
> "Dois detalhes vêm das limitações do hardware: **(1)** cada registrador guarda
> só 32 bits, então usamos **4 registradores** para os 128 bits do token; e
> **(2)** o compilador recusa uma comparação com quatro `&&` de uma vez — fica
> 'complexa demais' para um estágio — então quebramos em **`if`s aninhados**.
> O efeito é o mesmo, mas aí compila."

Frase de fechamento do bloco (a ideia central):
> "A mudança essencial em relação ao esqueleto é a **ordem**: o roteamento
> (`forward.apply()`) deixou de ser a primeira coisa e passou a ser a **última**
> — só acontece depois de o pacote **provar** que tem o token certo."

### Bloco 5 — Demonstração (2 min)
Veja o passo a passo no 5.2.

### Bloco 6 — Conclusão (30s)
> "Todos os requisitos foram cumpridos: token de 16 bytes na SRAM, gravação via
> pacote de configuração, validação por comparação e roteamento condicional.
> Possíveis evoluções seriam remover o token antes de entregá-lo ao destino e
> proteger o token com criptografia — fora do escopo deste trabalho."

---

## 5.2 Demonstração ao vivo (passo a passo)

> Faça um "ensaio" antes. Tenha **dois terminais** abertos no container.

**Preparação (uma vez):**
```bash
# dentro do container p4studio
cd project/src    # ajuste conforme onde clonou
cd ../simulator
./p4_build.sh secret        # compila o P4
./start_switch.sh secret    # sobe switch + simulador + setup.py
# saia do tmux com CTRL+b depois d
```

**Terminal 1 — observar a saída (Porta 2 / veth8):**
```bash
sudo tcpdump -i veth8 -e
```

**Terminal 2 — injetar os pacotes:**
```bash
sudo python3 test_tunnel.py
```

**O que narrar enquanto roda:**
1. *"Passo [1]: mandei o pacote `0x9000` com o token correto. Ele **gravou** o
   token e foi descartado — repare que **nada** apareceu no tcpdump."*
2. *"Passo [2]: mandei uma mensagem `0x9001` com o token **errado**. O switch
   comparou com a memória, não bateu, e **dropou** — de novo, nada no
   tcpdump."*
3. *"Passo [3]: mandei a mensagem `0x9001` com o token **certo**. Agora sim — o
   pacote **apareceu** na veth8. O filtro funcionou: só o pacote autenticado
   passou."*

> Se quiser um efeito extra, mostre que mudar `MEU_TOKEN` no script faz o passo
> [3] também ser bloqueado (porque não bate mais com o que está gravado).

---

## 5.3 Perguntas que o professor pode fazer (com respostas)

**P: O que é o plano de dados e o plano de controle?**
> Plano de dados é o processamento **por pacote**, em velocidade de linha,
> programado em P4. Plano de controle é a parte que **configura** o switch
> (tabelas, portas) de vez em quando, rodando numa CPU comum — aqui, o
> `setup.py`. O enunciado disse para não mexer no controle.

**P: Por que 4 registradores e não 1?**
> Porque cada registrador do Tofino guarda no máximo 32 bits, e o token tem
> 128. `128 / 32 = 4`. Além disso, um registrador só pode ser acessado uma vez
> por pacote; com quatro, conseguimos gravar/ler os quatro pedaços no mesmo
> pacote sem violar essa regra.

**P: Por que os `if`s aninhados em vez de um `&&`?**
> Uma condição com quatro comparações de 32 bits unidas por `&&` estoura a
> capacidade de avaliação de um único estágio do pipeline, e o `p4c` dá erro de
> *"condition too complex"*. Aninhando os `if`s, cada comparação cabe no
> hardware. O resultado lógico é o mesmo: só passa quem acerta os quatro
> pedaços.

**P: Como o token é gravado dentro do switch?**
> Um pacote com EtherType `0x9000` carrega o token. O parser o extrai, e no
> `apply` o switch fatia os 128 bits em quatro e escreve cada parte num
> registrador com `.write(0, ...)`. Depois descarta esse pacote, porque ele era
> só configuração.

**P: O que é o EtherType e por que usaram `0x9000`/`0x9001`?**
> EtherType é um campo de 16 bits do cabeçalho Ethernet que diz "o que vem
> depois". Escolhemos dois valores livres para diferenciar nossos dois tipos de
> pacote: `0x9000` = gravar o token, `0x9001` = mensagem a validar. O parser usa
> esse campo num `select` para decidir se lê o cabeçalho secreto.

**P: O que acontece com um pacote Ethernet comum (sem token)?**
> Cai no `else` final e é descartado. É uma postura "nega por padrão": só passa
> quem fala o protocolo do túnel. Se quiséssemos que o switch também roteasse
> tráfego comum, bastaria chamar `forward.apply()` nesse `else`.

**P: O registrador não perde o valor quando o pacote vai embora?**
> Não. Registradores são **memória persistente** (SRAM) do chip: o valor
> sobrevive entre pacotes. Por isso o token gravado no primeiro pacote ainda
> está lá quando os pacotes seguintes chegam para validação. Isso é diferente
> das metadatas (`meta`), que zeram a cada pacote.

**P: Por que vocês duplicaram o parser no egress?**
> Depois do roteamento, o pacote passa de novo por um parser, o de saída. Como o
> pacote válido ainda carrega o cabeçalho secreto, espelhamos a lógica no egress
> para que a saída enxergue e remonte o pacote de forma coerente. É uma medida
> defensiva.

**P: Como vocês testaram?**
> Com Scapy, em Python (recomendado pelo enunciado). O `test_tunnel.py` cria três
> pacotes — grava o token, manda um com token errado e um com token certo — e
> observamos com `tcpdump` na interface de saída que só o pacote correto passa.

**P: Qual a fragilidade de segurança dessa solução?**
> O token trafega em texto puro; quem capturar o pacote de configuração vê o
> segredo e pode reusá-lo. Numa solução real usaríamos criptografia. Aqui o foco
> é didático: entender plano de dados, registradores e match-action.

**P: O que é PISA / TNA?**
> PISA é o modelo de arquitetura de switch programável (parser → match-action →
> deparser, em esteira). TNA (*Tofino Native Architecture*) é o "dialeto" de P4
> específico do chip Tofino, que define os blocos que nosso programa preenche e
> as metadatas para conversar com o hardware.

---

## 5.4 Glossário-relâmpago (cola para a mão)

| Termo | Em uma linha |
|-------|--------------|
| **P4** | Linguagem que programa o que o switch faz com cada pacote. |
| **Plano de dados** | Processamento por pacote (P4). |
| **Plano de controle** | Configuração do switch (`setup.py`); não mexemos. |
| **PISA** | Arquitetura em esteira: parser → match-action → deparser. |
| **Tofino / TNA** | Chip programável da Intel / seu dialeto de P4. |
| **Parser** | Máquina de estados que lê os bytes em cabeçalhos. |
| **Header** | Molde de um cabeçalho (struct com bit de "válido"). |
| **Tabela (match-action)** | Casa uma chave e dispara uma ação. |
| **Ação** | Código executado quando a tabela casa. |
| **Registrador** | Memória persistente (SRAM) que sobrevive entre pacotes. |
| **Metadata** | Variáveis de rascunho do pacote; zeram a cada pacote. |
| **Deparser** | Remonta os cabeçalhos em bytes para a saída. |
| **EtherType** | Campo do Ethernet que diz "o que vem depois". |
| **drop_ctl** | Campo que, em `1`, faz o switch descartar o pacote. |
| **ucast_egress_port** | Campo que define a porta de saída do pacote. |

---

Boa apresentação! Se você entendeu os **três fluxos** e os **dois truques de
hardware**, você entendeu o trabalho. O resto é vocabulário.
