/* ===========================================================================
 * headers.p4 — DEFINIÇÃO DOS FORMATOS DOS CABEÇALHOS
 * ---------------------------------------------------------------------------
 * [DIDÁTICO] Este arquivo é só "moldes": ele diz QUAIS cabeçalhos existem e o
 * tamanho exato de cada campo. Pense em cada `header` como uma `struct` de C
 * com bitfields. Aqui não há lógica nenhuma — a leitura fica no parser.p4 e a
 * decisão fica no secret.p4. (Veja docs/02-anatomia-de-um-programa-p4.md.)
 * =========================================================================== */

#ifndef _HEADERS_           // [DIDÁTICO] include guard, idêntico ao de C
#define _HEADERS_

#include <core.p4>          // [DIDÁTICO] tipos básicos do P4 (packet_in, etc.)
#include <v1model.p4>

#if __TARGET_TOFINO__ == 3
#include <t3na.p4>
#elif __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

// [DIDÁTICO] `typedef` funciona como em C. `bit<N>` é um inteiro sem sinal de
// N bits exatos (em P4 não existe `int`; o hardware mexe bit a bit).
typedef bit<48> mac_addr_t;
typedef bit<16> ether_type_t;

/* 1. Primeiro definimos os moldes dos cabeçalhos */
header ethernet_h {
    mac_addr_t dst_addr;     // 48 bits
    mac_addr_t src_addr;     // 48 bits
    bit<16> ether_type;      // [DIDÁTICO] diz "o que vem depois"; usamos p/ achar nossos pacotes
}

// [DIDÁTICO] ADICIONADO NO TRABALHO: o nosso cabeçalho próprio.
// O token tem 128 bits = 16 bytes, exatamente o tamanho pedido no enunciado.
header secret_h {
    bit<128> token;
}

/* 2. Instanciamos os moldes já conhecidos dentro da struct global */
// [DIDÁTICO] `header_t` é a lista de TODOS os cabeçalhos que um pacote pode ter.
// Todo header carrega, escondido, um bit de "válido?": só fica válido quando o
// parser faz extract, e só o que é válido é re-emitido pelo deparser.
struct header_t {
    ethernet_h ethernet;
    secret_h   secret;       // [DIDÁTICO] ADICIONADO NO TRABALHO
}

/* 3. Estrutura de metadados auxiliares */
// [DIDÁTICO] `metadata_t` é o "rascunho" do pacote: variáveis que vivem só
// durante a passagem deste pacote pela esteira e zeram para o próximo (como
// variáveis locais em C). Aqui aux1..aux4 guardam os 4 pedaços do token lido
// da memória para depois comparar. Esta struct já vinha pronta do professor.
struct metadata_t {
    bit<32> aux1;
    bit<32> aux2;
    bit<32> aux3;
    bit<32> aux4;
    bit<128> aux5;
}

#endif /* _HEADERS_ */