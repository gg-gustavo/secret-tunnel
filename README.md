

## 🛡️ Guia de Execução e Testes: Túnel Secreto L2 (P4 Tofino)

Este documento detalha o passo a passo para inicializar o ambiente virtualizado do Tofino, compilar o plano de dados (*Data Plane*) e executar o script de validação do Túnel Secreto para testar a arquitetura de *Default Deny* e fatiamento na SRAM.

---

### 📌 Pré-requisitos

Certifique-se de que o Docker e o Docker Compose estão instalados e rodando na máquina host. O terminal host deve estar na raiz do projeto onde se encontra o arquivo `docker-compose.yml`.

### Passo 1: Subindo o Ambiente Virtual

Primeiro, inicializamos o container que contém as ferramentas da Intel/Barefoot (SDE) em segundo plano.

No seu terminal (host), execute:

```bash
docker-compose up -d

```

> **Nota:** Aguarde alguns segundos para garantir que o container `p4studio` inicializou completamente antes de prosseguir.

---

### Passo 2: Compilando o Código P4

Vamos acessar o container e compilar a nossa solução. O compilador irá gerar o binário otimizado para a arquitetura PISA.

1. Acesse o ambiente isolado do container:
```bash
docker exec -ti p4studio bash

```


2. Navegue até a pasta do simulador e dispare o *build*:
```bash
cd ~/project/simulator
./p4_build.sh secret

```



---

### Passo 3: Ligando o Switch e o Plano de Controle

Com o binário gerado, vamos carregá-lo no chip simulado e inicializar as regras estáticas de roteamento via Python.

Ainda no diretório `/simulator`, execute:

```bash
./start_switch.sh secret

```

A tela será dividida (TMUX). Do lado esquerdo, o *Control Plane* (`setup.py`) inserirá as regras de MAC. Do lado direito, os logs do ASIC Tofino serão exibidos.

**Como sair sem desligar o switch:**
Assim que os logs pararem de rolar, faça o *detach* da sessão para deixar o switch rodando de forma segura em *background*:

* Pressione e segure **`Ctrl`**
* Dê um toque na tecla **`B`**
* Solte ambas as teclas
* Pressione a tecla **`D`**

---

### Passo 4: Preparando o Monitoramento (Terminal 1)

Agora que você voltou ao *prompt* normal do container, vamos configurar um "espião" na porta física de saída do switch (Porta 2, mapeada para `veth8`).

Execute o comando abaixo para escutar a rede em tempo real:

```bash
sudo tcpdump -i veth8 -e -n

```

*Deixe este terminal aberto e visível. Ele ficará aguardando a chegada dos pacotes.*

---

### Passo 5: Executando a Injeção de Pacotes (Terminal 2)

Para testarmos a filtragem, precisaremos de uma **nova aba ou janela** de terminal no sistema host para disparar o tráfego.

1. Na nova janela, entre novamente no container:
```bash
docker exec -ti p4studio bash

```


2. Vá para a raiz do projeto (onde está o script Python):
```bash
cd ~/project

```


3. Dispare o injetor de pacotes (Scapy):
```bash
sudo python3 test_tunnel.py

```



---

### 📊 Análise dos Resultados

Ao rodar o script no **Terminal 2**, observe imediatamente o *output* do `tcpdump` no **Terminal 1**. O comportamento esperado do hardware é:

1. **Teste de Gravação (`0x9000`):** O pacote envia a senha original de 16 bytes para a SRAM. O switch grava e destrói o pacote voluntariamente. **Resultado: O `tcpdump` deve ignorar.**
2. **Teste Inválido (`0x9001` - Payload Incorreto):** O pacote tenta atravessar usando o token `BBBB...`. A máquina de estados faz a checagem bit a bit, detecta a fraude e aciona o *Drop* antes de acessar a tabela de roteamento. **Resultado: O `tcpdump` deve ignorar.**
3. **Teste Válido (`0x9001` - Payload Correto):** O pacote apresenta o token `AAAA...`. O *match* é perfeito, a tabela estática (`forward`) é liberada e o pacote é encaminhado para a interface física correta. **Resultado: O pacote aparece no `tcpdump`.**

**Saída de Sucesso Esperada no tcpdump:**

```text
listening on veth8, link-type EN10MB (Ethernet), snapshot length 262144 bytes
23:09:39.036764 00:00:00:00:00:01 > 00:00:00:00:00:02, ethertype Unknown (0x9001), length 60: 
        0x0000:  aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa  ................
        0x0010:  0000 0000 0000 0000 0000 0000 0000 0000  ................
        0x0020:  0000 0000 0000 0000 0000 0000 0000       ..............

```
