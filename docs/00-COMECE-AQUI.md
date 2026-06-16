# 📚 Material de Estudo — Trabalho "Túnel Secreto" (P4 / Tofino)

> Este conjunto de documentos foi escrito para você **aprender P4 do zero**
> (assumindo que você já conhece C) e conseguir **apresentar este trabalho**
> com segurança, explicando o que o professor forneceu e o que foi
> implementado pelo seu colega.

## Como usar este material

Leia na ordem. Cada documento é curto e se apoia no anterior.

| # | Documento | O que você aprende |
|---|-----------|--------------------|
| 1 | [01-fundamentos-p4-e-pisa.md](01-fundamentos-p4-e-pisa.md) | O que é P4, o que é um switch programável, a arquitetura PISA e o chip Tofino. A "visão geral" antes de olhar código. |
| 2 | [02-anatomia-de-um-programa-p4.md](02-anatomia-de-um-programa-p4.md) | As peças de um programa P4 (headers, parser, tabelas, ações, registradores, deparser) — cada uma comparada com algo que você já conhece em C. |
| 3 | [03-o-trabalho-passo-a-passo.md](03-o-trabalho-passo-a-passo.md) | O trabalho em si: o que veio do professor, o que o colega mudou, linha por linha, e **por quê**. |
| 4 | [04-requisitos-atendidos.md](04-requisitos-atendidos.md) | Checklist: o enunciado pediu X, o código entrega Y. Prova de que o trabalho está completo. |
| 5 | [05-roteiro-de-apresentacao.md](05-roteiro-de-apresentacao.md) | Roteiro de fala, demonstração ao vivo e **perguntas que o professor pode fazer** (com respostas). |

## 🖥️ Slides prontos para apresentar

- [slides.md](slides.md) — apresentação em formato **Marp** (Markdown → slides).
- [slides.html](slides.html) — **versão já renderizada**: abra no navegador e
  navegue com as setas `→`/`←` (aperte `F` para tela cheia).
- [como-ver-os-slides.md](como-ver-os-slides.md) — como editar, visualizar no
  VS Code e **exportar para PDF/PowerPoint**.

## Resumo de uma frase

> O trabalho transforma um switch de rede em um **"porteiro"**: ele só deixa
> um pacote passar para o destino se esse pacote carregar um **token secreto
> de 16 bytes** idêntico ao que foi previamente gravado na memória do switch.

## O mapa mental do trabalho (decore esta figura)

```
                  PACOTE 0x9000 (configuração)
                  "grave este token na sua memória"
   veth0  ───────────────────────────────────────►  [ SWITCH ]
                                                       grava token
                                                       e descarta o pacote
                                                       (X — não vai a lugar nenhum)

                  PACOTE 0x9001 (mensagem) com token ERRADO
   veth0  ───────────────────────────────────────►  [ SWITCH ]  ──X  (dropado)

                  PACOTE 0x9001 (mensagem) com token CERTO
   veth0  ───────────────────────────────────────►  [ SWITCH ]  ────►  veth8 (destino)
```

- **0x9000** e **0x9001** são "EtherTypes" — um número no cabeçalho Ethernet
  que o colega escolheu para diferenciar os dois tipos de pacote
  ("estou gravando o token" vs. "estou enviando uma mensagem").
- O **token** tem 128 bits (16 bytes) e fica guardado dentro do switch em
  uma memória que sobrevive entre pacotes (os **registradores / SRAM**).

## Arquivos que importam neste repositório

| Arquivo | Papel |
|---------|-------|
| [src/secret/headers.p4](../src/secret/headers.p4) | Define os **formatos** dos cabeçalhos (Ethernet e o nosso "secret"). |
| [src/secret/parser.p4](../src/secret/parser.p4) | Define como o switch **lê** os bytes do pacote e remonta a saída. |
| [src/secret/secret.p4](../src/secret/secret.p4) | O **cérebro**: a lógica de gravar o token, validar e rotear/dropar. |
| [test_tunnel.py](../test_tunnel.py) | Script de teste em Python/Scapy que **fabrica e envia** os 3 pacotes. |
| [src/secret/setup.py](../src/secret/setup.py) | Control plane: configura as portas e preenche a tabela de roteamento. (Fornecido pelo professor — não precisamos mexer.) |

> Dica: cada arquivo `.p4` ganhou **comentários didáticos** marcados com a
> tag `[DIDÁTICO]`. Eles foram adicionados só para o seu estudo e explicam o
> conceito de P4 naquela linha.
