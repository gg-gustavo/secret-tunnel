# Trabalho de Redes 1 2026/1 - Túnel secreto

A ideia geral desse trabalho é implementar um mecanismo de filtragem
de mensagens dentro do switch.
As mensagens só devem ser roteadas corretamente se carregarem um token
secreto, configurável, previamente gravado dentro da SRAM do switch
programável.

Como não dispomos de um switch físico para implementação deste algoritmo,
utilizaremos um simulador do chip Intel Tofino, que implementa a 
arquitetura PISA para switches programáveis.

## Utilizando o switch

### Requisitos

Caso já não o tenha feito,
será necessário instalar o Docker para utilizar o ambiente deste projeto.
Confira a seguinte página para instruções:
https://docs.docker.com/engine/install

### Executando o simulador

Utilizaremos um container Docker com o simulador já instalado e configurado.

Primeiro passo após clonar este repositório é subir o container e acessá-lo:
```bash
cd trabalho_p4_redes1_2026_01/simulator
# Baixa a imagem do container
docker compose pull
# Inicia o container
docker compose up -d
# Abre uma shell Bash dentro do container
docker exec -ti p4studio bash
```

Uma vez dentro do container, precisamos instalar as dependências de
desenvolvimento deste projeto:
```bash
cd project
./setup.sh
source ~/.bashrc
```

Com as dependências devidamente instaladas podemos inicializar a simulação do switch:
```bash
cd simulator
# Compila o código P4
./p4_build.sh secret
# Inicializa o control plane e o simulador Tofino
./start_switch.sh secret
```

Isto irá abrir um painel do TMUX, onde o painel da esquerda executa o software de control
plane, e o painél da direita executa o simulador do Tofino.
Não será necessário interagir com nenhum desse componentes, então é simplesmente
sair dessa sessão do TMUX (CTRL + b + d).

Caso queira brincar com o simulador e voltar pra sessão TMUX:
```bash
tmux attach -t switch
```

Se quisar matar o switch:
```bash
tmux kill-session -t switch
```

### Interagindo com o switch

Para enviar dados pelo switch, utilize as seguintes interfaces já configuradas:

Nome da porta | Interface Virtual | MAC
------- | ------- | ----
1/0 | veth0 | 00:00:00:00:00:01 
2/0 | veth8 | 00:00:00:00:00:02
3/0 | veth16 | 00:00:00:00:00:03

Todas as portas são interagíveis através de interfaces ethernet virtuais
inicializadas junto com o switch.
Por exemplo, para monitorar todos os pacotes que saem da Porta 3 do switch
basta monitorar a 'veth16':
```bash
sudo tcpdump -i veth16
```


## Requisitos funcionais do trabalho

Como citado anteriormente, somente pacotes que carreguem o token secreto correto
podem ser roteados corretamente. Este token deve ser de 16 bytes.
O chip Tofino dispõe de registradores que permitem o armazenamento de dados
no próprio switch, então esse segredo deve ser armazenado nos registradores
para posterior consulta.
Você deve construir uma maneira de gravar esse token no switch.

Com o token gravado no switch, crie também um mecanismo para transportar
uma mensagem qualquer, que também carrega o token secreto.
Caso o token secreto seja o mesmo do gravado dentro do switch, a mensagem
trafega normalmente, do contrário ela é dropada.

Exemplos:
```txt
                            ____________________
                            |Switch             |
                            |       TOKEN       |
                            |         ^         |
                            |         |         |
Pacote que grava o token ----------------------X|   Destino     
                            |___________________|
                            


                            ____________________
                            |Switch             |
                            |       TOKEN       |
                            |         ^         |
                            |         |         |
Mensagem sem token secreto ---------Match?-----X|   Destino     
                            |___________________|


                            ____________________
                            |Switch             |
                            |       TOKEN       |
                            |         ^         |
                            |         |         |
Mensagem com token secreto ---------Match?---------->Destino     
                            |___________________|
```


### O que deve ser entregue?

Os arquivos fonte:
- headers.p4
- parser.p4
- secret.p4

E quaisquer scripts adicionais utilizados para testar o trabalho.

## Recomendações


### Materiais de estudo

- Documentação do P4: https://p4.org/wp-content/uploads/sites/53/2024/10/P4-16-spec-v1.2.5.html
- Exercícios P4: https://github.com/p4lang/tutorials
- Especificações do Tofino: https://raw.githubusercontent.com/barefootnetworks/Open-Tofino/master/PUBLIC_Tofino-Native-Arch.pdf
- Arquitetura de switchs programáveis: https://sdn.systemsapproach.org/switch.html

### Dicas

- Pra criar os pacotes e protótipos, utilize `scapy` do python.
- Tente fazer o simples (a funcionalidade é simples)
- Não precisa mexer no control plane
- É programação baixo nível, não tenha medo de fazer código feio


### Dúvidas

Enviem suas dúvidas pra: evsenoski@inf.ufpr.br
