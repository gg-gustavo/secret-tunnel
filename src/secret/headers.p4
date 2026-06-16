#ifndef _HEADERS_
    #define _HEADERS_

#include <core.p4>
#include <v1model.p4>

#if __TARGET_TOFINO__ == 3
#include <t3na.p4>
#elif __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

typedef bit<48> mac_addr_t;
typedef bit<16> ether_type_t;

/* Define os moldes dos cabeçalhos */
header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    bit<16> ether_type;
}

header secret_h {
    bit<128> token;
}

/* Instancia os moldes dentro da struct global */
struct header_t {
    ethernet_h ethernet;
    secret_h   secret;
}

/* Variáveis metadados auxiliares */
struct metadata_t {
    bit<32> aux1;
    bit<32> aux2;
    bit<32> aux3;
    bit<32> aux4;
    bit<128> aux5;
}

#endif /* _HEADERS_ */
