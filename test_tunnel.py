# =============================================================================
# test_tunnel.py — GERA E ENVIA OS PACOTES DE TESTE (com Scapy)
# -----------------------------------------------------------------------------
# [DIDÁTICO] Scapy é uma biblioteca Python para "fabricar" pacotes byte a byte.
# Aqui montamos os 3 pacotes que exercitam os 3 fluxos do switch (ver
# docs/03-o-trabalho-passo-a-passo.md, seção 3.4) e os injetamos na veth0
# (= Porta 1 do switch). Para VER o resultado, rode em outro terminal:
#     sudo tcpdump -i veth8        (veth8 = Porta 2, o destino)
# Só o pacote do passo [3] (token correto) deve aparecer lá.
# =============================================================================

from scapy.all import Ether, sendp, bind_layers, Packet
from scapy.fields import BitField
import time

# Definindo o molde do Túnel Secreto no Python
# [DIDÁTICO] Este é o espelho, em Python, do `header secret_h { bit<128> token }`
# do headers.p4: um campo "token" de 128 bits (16 bytes).
class SecretHeader(Packet):
    name = "SecretHeader"
    fields_desc = [ BitField("token", 0, 128) ] # 16 bytes

# Ensinando o Scapy a conectar o Ethernet com o nosso cabeçalho
# [DIDÁTICO] bind_layers diz ao Scapy: "se o EtherType for 0x9000/0x9001, o que
# vem depois do Ethernet é um SecretHeader". É o equivalente, no Python, ao
# `transition select(ether_type)` do parser.p4.
bind_layers(Ether, SecretHeader, type=0x9000)
bind_layers(Ether, SecretHeader, type=0x9001)

MAC_PORTA_1 = "00:00:00:00:00:01" # Entrada (veth0)
MAC_PORTA_2 = "00:00:00:00:00:02" # Saída (veth8)
INTERFACE = "veth0"

# Tokens
# [DIDÁTICO] dois valores de 128 bits: um que SERÁ gravado (o "certo") e outro
# para testar a rejeição (o "errado").
MEU_TOKEN = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
TOKEN_ERRADO = 0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB

print("=== Iniciando Teste do Túnel Secreto ===")

# [DIDÁTICO] PASSO 1 -> aciona o FLUXO A (0x9000): o switch grava o token na SRAM
# e descarta o pacote. Nada deve sair na veth8.
print("\n[1] Gravando o Token na SRAM (0x9000)...")
pkt_config = Ether(src=MAC_PORTA_1, dst=MAC_PORTA_2, type=0x9000) / SecretHeader(token=MEU_TOKEN)
sendp(pkt_config, iface=INTERFACE, verbose=False)
time.sleep(1)   # [DIDÁTICO] garante que o token já está gravado antes de validar

# [DIDÁTICO] PASSO 2 -> FLUXO B com token ERRADO: a comparação falha -> DROP.
# Nada deve sair na veth8.
print("\n[2] Injetando mensagem com token INVÁLIDO (0x9001)...")
pkt_invalido = Ether(src=MAC_PORTA_1, dst=MAC_PORTA_2, type=0x9001) / SecretHeader(token=TOKEN_ERRADO)
sendp(pkt_invalido, iface=INTERFACE, verbose=False)
time.sleep(1)

# [DIDÁTICO] PASSO 3 -> FLUXO B com token CERTO: os 4 pedaços batem -> o switch
# chama forward.apply() e o pacote SAI pela veth8 (Porta 2). Este é o único que
# deve aparecer no tcpdump.
print("\n[3] Injetando mensagem com token VÁLIDO (0x9001)...")
pkt_valido = Ether(src=MAC_PORTA_1, dst=MAC_PORTA_2, type=0x9001) / SecretHeader(token=MEU_TOKEN)
sendp(pkt_valido, iface=INTERFACE, verbose=False)

print("\n=== Fim da Transmissão ===")
