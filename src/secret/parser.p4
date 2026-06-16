/* ===========================================================================
 * parser.p4 — COMO O SWITCH LÊ E REMONTA O PACOTE
 * ---------------------------------------------------------------------------
 * [DIDÁTICO] Um parser é uma MÁQUINA DE ESTADOS (pense em switch + goto, em C):
 * ele lê os bytes crus do pacote com `extract` e os encaixa nos headers do
 * headers.p4. Há dois lados na "esteira" PISA: Ingress (entrada) e Egress
 * (saída), cada um com seu parser e seu deparser. O deparser faz o inverso:
 * `emit` serializa os headers válidos de volta em bytes.
 * (Veja docs/02-anatomia-de-um-programa-p4.md, seções 2.4 e 2.10.)
 * =========================================================================== */

#ifndef _PARSER_
    #define _PARSER_

/* ===================================================== Tofino Parsers ===================================================== */

/* -------------------- NÃO ALTERAR NENHUM DOS COMPONENTES DESTE BLOCO ----------------------------- */
/* [DIDÁTICO] Este bloco é "boilerplate" do Tofino: trata metadados internos do
 * chip (resubmit, port metadata). Vem pronto do professor e não se mexe. */

parser TofinoIngressParser(
        packet_in pkt,
        out ingress_intrinsic_metadata_t ig_intr_md)
{
    state start {
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag) {
            1 : parse_resubmit;
            0 : parse_port_metadata;
        }
    }

    state parse_resubmit {
        transition reject; // parse resubmitted packet here.
    }

    state parse_port_metadata {
        pkt.advance(PORT_METADATA_SIZE);
        transition accept;
    }
}

parser TofinoEgressParser(
        packet_in pkt,
        out egress_intrinsic_metadata_t eg_intr_md)
{
    state start {
        pkt.extract(eg_intr_md);
        transition accept;
    }
}

/* ===================================================== Ingress ===================================================== */

// ---------------------------------------------------------------------------
// Ingress Parser
// ---------------------------------------------------------------------------
parser SwitchIngressParser(packet_in pkt,
    /* User */
    out header_t        hdr,
    out metadata_t      meta,
    /* Intrinsic */
    out ingress_intrinsic_metadata_t ig_intr_md)
{
    TofinoIngressParser() tofino_parser;

    state start {
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        meta = {0, 0, 0, 0, 0};        // [DIDÁTICO] zera o rascunho (5 campos de metadata_t)
        pkt.extract(hdr.ethernet);     // [DIDÁTICO] lê 14 bytes -> hdr.ethernet vira "válido"

        /* NOSSO CÓDIGO: Transição condicional baseada no EtherType */
        // [DIDÁTICO] `transition select` é o `switch` do P4: olha o ether_type e
        // decide o próximo estado. Só os nossos tipos especiais têm token a ler.
        transition select(hdr.ethernet.ether_type) {
            0x9000: parse_secret;      // pacote de GRAVAÇÃO do token
            0x9001: parse_secret;      // pacote de MENSAGEM (a validar)
            default: accept;           // [DIDÁTICO] qualquer outro: não tem token, para aqui
        }
    }

    /* Estado criado para extrair os 16 bytes do token */
    // [DIDÁTICO] só depois deste extract é que hdr.secret.token tem valor usável
    // na lógica do secret.p4. Sem este estado, o token seria invisível.
    state parse_secret {
        pkt.extract(hdr.secret);       // lê 128 bits (16 bytes) -> hdr.secret
        transition accept;
    }
}

// ---------------------------------------------------------------------------
// Ingress Deparser
// ---------------------------------------------------------------------------
control SwitchIngressDeparser(packet_out pkt,
    /* User */
    inout header_t      hdr,
    in metadata_t       meta,
    /* Intrinsic */
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md)
{
    apply {
        // [DIDÁTICO] emit é o inverso de extract: escreve de volta no fio TODOS
        // os headers VÁLIDOS, em ordem. Headers inválidos simplesmente não saem.
        pkt.emit(hdr); // Remonta o pacote para a saída
    }
}

/* ===================================================== Egress ===================================================== */

// ---------------------------------------------------------------------------
// Egress Parser
// ---------------------------------------------------------------------------
parser SwitchEgressParser(packet_in pkt,
    /* User */
    out header_t        hdr,
    out metadata_t      meta,
    /* Intrinsic */
    out egress_intrinsic_metadata_t eg_intr_md)
{
    TofinoEgressParser() tofino_parser;

    state start {
        tofino_parser.apply(pkt, eg_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        meta = {0, 0, 0, 0, 0};
        pkt.extract(hdr.ethernet);

        /* Espelhamos a lógica do Ingress para evitar falhas no pipeline de saída */
        // [DIDÁTICO] Depois do Traffic Manager o pacote é RE-PARSEADO aqui na
        // saída. Um pacote válido ainda carrega o header secret; espelhar a
        // lógica garante que a saída o enxergue e o remonte de forma coerente.
        transition select(hdr.ethernet.ether_type) {
            0x9000: parse_secret;
            0x9001: parse_secret;
            default: accept;
        }
    }

    state parse_secret {
        pkt.extract(hdr.secret);
        transition accept;
    }
}

// ---------------------------------------------------------------------------
// Egress Deparser
// ---------------------------------------------------------------------------
control SwitchEgressDeparser(packet_out pkt,
    /* User */
    inout header_t      hdr,
    in metadata_t       meta,
    /* Intrinsic */
    in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md)
{
    apply {
        pkt.emit(hdr);
    }
}

#endif /* _PARSER_ */