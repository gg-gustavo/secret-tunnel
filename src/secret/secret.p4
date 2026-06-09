#include <core.p4>
#if __TARGET_TOFINO__ == 3
#include <t3na.p4>
#elif __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "headers.p4"
#include "parser.p4"

/* ===================================================== Ingress ===================================================== */

control SwitchIngress(
    /* User */
    inout header_t      hdr,
    inout metadata_t    meta,
    /* Intrinsic */
    in ingress_intrinsic_metadata_t                     ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t         ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t     ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t           ig_tm_md)
{
    /* Ações de Encaminhamento */
    action hit(PortId_t port) {
        ig_tm_md.ucast_egress_port = port; // Define a porta física de saída 
    }

    action miss(bit<3> drop) {
        ig_dprsr_md.drop_ctl = drop; // Marca o pacote para descarte no deparser
    }

    /* Tabela de Roteamento L2 fornecida pelo professor */
    table forward {
        key = {
            hdr.ethernet.dst_addr : exact;
        }
        actions = {
            hit;
            @defaultonly miss; 
        }
        const default_action = miss(0x1); 
        size = 1024;
    }

    /* --- INSTANCIAÇÃO DOS REGISTRADORES (SRAM) ---
       Criamos 4 arrays independentes de tamanho 1, armazenando 32 bits cada,
       indexados por uma chave de 1 bit (posição 0).
    */
    Register<bit<32>, bit<1>>(1) secret_reg1;
    Register<bit<32>, bit<1>>(1) secret_reg2;
    Register<bit<32>, bit<1>>(1) secret_reg3;
    Register<bit<32>, bit<1>>(1) secret_reg4;

    apply {
        /* LÓGICA DO TÚNEL SECRETO (Default Deny / Bloqueio Padrão) */
        
        if (hdr.ethernet.ether_type == 0x9000) {
            /* FLUXO A: Gravação */
            secret_reg1.write((bit<1>)0, hdr.secret.token[31:0]);
            secret_reg2.write((bit<1>)0, hdr.secret.token[63:32]);
            secret_reg3.write((bit<1>)0, hdr.secret.token[95:64]);
            secret_reg4.write((bit<1>)0, hdr.secret.token[127:96]);
            
            ig_dprsr_md.drop_ctl = 1;
        }
        else if (hdr.ethernet.ether_type == 0x9001) {
            /* FLUXO B: Validação */
            meta.aux1 = secret_reg1.read((bit<1>)0);
            meta.aux2 = secret_reg2.read((bit<1>)0);
            meta.aux3 = secret_reg3.read((bit<1>)0);
            meta.aux4 = secret_reg4.read((bit<1>)0);

            /* Aninhamento Sequencial Seguro
               Isso evita o erro de 'condition too complex' do compilador 
               e obriga o chip a validar as 4 fatias antes de qualquer coisa.
            */
            if (hdr.secret.token[31:0] == meta.aux1) {
                if (hdr.secret.token[63:32] == meta.aux2) {
                    if (hdr.secret.token[95:64] == meta.aux3) {
                        if (hdr.secret.token[127:96] == meta.aux4) {
                            
                            /* SUCESSO ABSOLUTO: O pacote provou ser autêntico.
                               Só agora ele ganha o direito de acessar a tabela de roteamento! */
                            forward.apply();
                            
                        } else { ig_dprsr_md.drop_ctl = 1; }
                    } else { ig_dprsr_md.drop_ctl = 1; }
                } else { ig_dprsr_md.drop_ctl = 1; }
            } else { ig_dprsr_md.drop_ctl = 1; }
        }
        else {
            /* Qualquer outro tipo de pacote é sumariamente destruído */
            ig_dprsr_md.drop_ctl = 1;
        }
    }
}

/* ===================================================== Egress ===================================================== */

control SwitchEgress(
    inout header_t      hdr,
    inout metadata_t    meta,
    in egress_intrinsic_metadata_t                      eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t          eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t      eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t   eg_oport_md) 
{
    apply {}
}

/* ===================================================== Final Pipeline ===================================================== */
Pipeline(
    SwitchIngressParser(),
    SwitchIngress(),
    SwitchIngressDeparser(),
    SwitchEgressParser(),
    SwitchEgress(),
    SwitchEgressDeparser()
) pipe;

Switch(pipe) main;