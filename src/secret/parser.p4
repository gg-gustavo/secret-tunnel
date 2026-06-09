#ifndef _PARSER_
    #define _PARSER_

/* ===================================================== Tofino Parsers ===================================================== */

/* -------------------- NÃO ALTERAR NENHUM DOS COMPONENTES DESTE BLOCO ----------------------------- */

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
        meta = {0, 0, 0, 0, 0};
        pkt.extract(hdr.ethernet);
        
        /* NOSSO CÓDIGO: Transição condicional baseada no EtherType */
        transition select(hdr.ethernet.ether_type) {
            0x9000: parse_secret;
            0x9001: parse_secret;
            default: accept;
        }
    }

    /* Estado criado para extrair os 16 bytes do token */
    state parse_secret {
        pkt.extract(hdr.secret);
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