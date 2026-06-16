# 4. O enunciado foi cumprido? (checklist + análise crítica)

> Objetivo: confrontar **cada exigência do enunciado** com o que o código
> entrega. Serve como "prova" na apresentação e te prepara para perguntas mais
> afiadas do professor.

## 4.1 Checklist dos requisitos funcionais

| # | O enunciado pede… | O código entrega? | Onde |
|---|-------------------|-------------------|------|
| 1 | Filtrar mensagens dentro do switch; só roteia quem tem o token | ✅ Sim | `secret.p4`, bloco `apply` (Fluxo B) |
| 2 | Token de **16 bytes** (128 bits) | ✅ Sim | `headers.p4`: `bit<128> token` |
| 3 | Token **gravado na SRAM** (registradores) do switch | ✅ Sim | `secret.p4`: 4× `Register<bit<32>,bit<1>>` |
| 4 | Uma **forma de gravar** o token no switch | ✅ Sim | Pacote `0x9000` → `secret_regN.write(...)` |
| 5 | Mensagem que **também carrega** o token | ✅ Sim | Pacote `0x9001` + header `secret_h` |
| 6 | Token igual ao gravado → **trafega**; diferente → **dropado** | ✅ Sim | `if` aninhado → `forward.apply()` / `drop_ctl=1` |

## 4.2 Checklist das entregas exigidas

O enunciado exige a entrega de:

| Arquivo pedido | Presente? | Observação |
|----------------|-----------|------------|
| `headers.p4` | ✅ | Com o header `secret_h` adicionado |
| `parser.p4` | ✅ | Com o estado `parse_secret` no ingress e egress |
| `secret.p4` | ✅ | Com toda a lógica do túnel |
| Scripts de teste | ✅ | `test_tunnel.py` (Scapy, como recomendado) |

**Conclusão:** todos os requisitos funcionais e todas as entregas exigidas
estão presentes. O trabalho está **completo e aderente ao enunciado**.

## 4.3 Conferindo contra os desenhos do enunciado

O enunciado ilustra 3 cenários. Veja como o código realiza cada um:

```
Pacote que grava o token ----X|            → Fluxo A: write(...) + drop_ctl=1   ✔
Mensagem SEM token secreto ---X| (Match?)   → Fluxo B: comparação falha + drop   ✔
Mensagem COM token secreto -----►Destino    → Fluxo B: comparação ok + forward   ✔
```

Os três batem exatamente com a implementação.

---

## 4.4 Análise crítica (para impressionar e para o Q&A)

Cumprir o básico está feito. Estes pontos mostram **entendimento profundo** —
ótimos para você levantar você mesmo na apresentação, ou responder se o
professor cutucar. **Não são erros**; são decisões de projeto e limites de
escopo.

### (a) O cabeçalho `secret` viaja junto até o destino

No fluxo de mensagem válida, o pacote é roteado **com** o cabeçalho `secret`
ainda anexado (o deparser emite todos os headers válidos). Ou seja, o destino
recebe o token junto.

- **É um problema?** Depende da interpretação de *"a mensagem trafega
  normalmente"*. O enunciado não pede para **remover** o token antes de
  entregar. Então está dentro do pedido.
- **Como seria "melhorar"?** Bastaria invalidar o header antes do deparser
  (`hdr.secret.setInvalid();`) no caminho de sucesso, e o token não sairia.
  É uma frase de uma linha — boa de citar como "evolução possível".

### (b) Default-deny: o switch só fala o protocolo secreto

O Fluxo C dropa **qualquer** pacote que não seja `0x9000`/`0x9001`. Isso
significa que tráfego Ethernet comum (sem token) **não passa** por este switch.

- **É um problema?** Não, para o escopo: o trabalho é justamente um "túnel
  secreto". É até a postura **mais segura** (nega por padrão).
- **Trade-off a citar:** se o objetivo fosse um switch "normal que também tem
  um túnel", você deixaria o `else` final rotear o tráfego comum
  (`forward.apply()`) em vez de dropar. É uma escolha de política, não um bug.

### (c) Segurança real: o token vai em texto puro

Qualquer um que capture o pacote `0x9000` (com `tcpdump`) **vê o token** e
poderia reusá-lo (ataque de repetição). Em sistemas reais, usaria-se
criptografia, nonce, etc.

- **Por que tudo bem aqui?** O objetivo é didático: entender plano de dados,
  registradores e match-action — não construir criptografia em hardware.
  Mencionar essa limitação mostra maturidade, sem desmerecer o trabalho.

### (d) Um único token global

Há um só token, na posição 0 dos registradores — um segredo compartilhado. O
enunciado pede exatamente isso ("um token secreto, configurável"). Suportar
vários tokens (por cliente/porta) seria uma extensão, não um requisito.

### (e) A API `.read()/.write()` dos registradores

No Tofino "de produção", o acesso a registradores normalmente é feito via
`RegisterAction`. Aqui usa-se a API simples `secret_regN.read(i)` /
`.write(i, v)` — que é **exatamente a que o professor indicou** nas dicas do
esqueleto. Ou seja, o colega seguiu a interface fornecida. Se o professor
perguntar "por que não RegisterAction?", a resposta é: *"segui a API
sugerida no enunciado; o conceito de acesso único por pacote foi respeitado."*

---

## 4.5 Veredito

> **O trabalho cumpre integralmente o enunciado**: token de 16 bytes gravado na
> SRAM via pacote de configuração, validação por comparação contra a memória, e
> roteamento condicionado ao token correto — com os arquivos exigidos
> (`headers.p4`, `parser.p4`, `secret.p4`) e um script de teste em Scapy.
>
> As observações da seção 4.4 são **limites de escopo e decisões de projeto**,
> não falhas. Levantá-las você mesmo demonstra que entendeu o trabalho a fundo.

➡️ Próximo: [05-roteiro-de-apresentacao.md](05-roteiro-de-apresentacao.md) —
como conduzir a apresentação, a demo ao vivo e responder o professor.
