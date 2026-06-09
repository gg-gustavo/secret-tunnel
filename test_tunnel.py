from scapy.all import Ether, sendp, bind_layers, Packet
from scapy.fields import BitField
import time

# Definindo o molde do Túnel Secreto no Python
class SecretHeader(Packet):
    name = "SecretHeader"
    fields_desc = [ BitField("token", 0, 128) ] # 16 bytes

# Ensinando o Scapy a conectar o Ethernet com o nosso cabeçalho
bind_layers(Ether, SecretHeader, type=0x9000)
bind_layers(Ether, SecretHeader, type=0x9001)

MAC_PORTA_1 = "00:00:00:00:00:01" # Entrada (veth0)
MAC_PORTA_2 = "00:00:00:00:00:02" # Saída (veth8)
INTERFACE = "veth0"

# Tokens
MEU_TOKEN = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
TOKEN_ERRADO = 0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB

print("=== Iniciando Teste do Túnel Secreto ===")

print("\n[1] Gravando o Token na SRAM (0x9000)...")
pkt_config = Ether(src=MAC_PORTA_1, dst=MAC_PORTA_2, type=0x9000) / SecretHeader(token=MEU_TOKEN)
sendp(pkt_config, iface=INTERFACE, verbose=False)
time.sleep(1)

print("\n[2] Injetando mensagem com token INVÁLIDO (0x9001)...")
pkt_invalido = Ether(src=MAC_PORTA_1, dst=MAC_PORTA_2, type=0x9001) / SecretHeader(token=TOKEN_ERRADO)
sendp(pkt_invalido, iface=INTERFACE, verbose=False)
time.sleep(1)

print("\n[3] Injetando mensagem com token VÁLIDO (0x9001)...")
pkt_valido = Ether(src=MAC_PORTA_1, dst=MAC_PORTA_2, type=0x9001) / SecretHeader(token=MEU_TOKEN)
sendp(pkt_valido, iface=INTERFACE, verbose=False)

print("\n=== Fim da Transmissão ===")
