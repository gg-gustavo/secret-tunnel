/* ===========================================================================
 * secret.p4 — O CÉREBRO DO TÚNEL SECRETO
 * ---------------------------------------------------------------------------
 * [DIDÁTICO] Aqui mora a LÓGICA por pacote. O bloco `apply` é como uma função
 * que roda uma vez para cada pacote. Ele implementa 3 fluxos:
 *   0x9000 -> grava o token nos registradores e descarta o pacote
 *   0x9001 -> lê os registradores, compara; igual roteia, diferente descarta
 *   outros -> descarta (nega por padrão)
 * Este é o arquivo de TOPO: ele dá #include nos outros dois e, no final, monta
 * a "esteira" PISA com Pipeline(...) + Switch(...) main.
 * (Veja docs/03-o-trabalho-passo-a-passo.md, seção 3.3.)
 * =========================================================================== */

#include <core.p4>
#if __TARGET_TOFINO__ == 3
#include <t3na.p4>
#elif __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "headers.p4"        // [DIDÁTICO] traz os moldes (ethernet_h, secret_h)
#include "parser.p4"         // [DIDÁTICO] traz os parsers/deparsers

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
    // [DIDÁTICO] Uma `action` é o corpo executado quando uma tabela "casa".
    action hit(PortId_t port) {
        ig_tm_md.ucast_egress_port = port; // Define a porta física de saída
    }

    action miss(bit<3> drop) {
        ig_dprsr_md.drop_ctl = drop; // Marca o pacote para descarte no deparser
    }

    /* Tabela de Roteamento L2 fornecida pelo professor */
    // [DIDÁTICO] Uma `table` é uma consulta configurável: pega a CHAVE (key),
    // procura na tabela e dispara a AÇÃO correspondente. QUEM PREENCHE as linhas
    // é o plano de controle (o setup.py: forward.add_with_hit(mac, porta)).
    table forward {
        key = {
            hdr.ethernet.dst_addr : exact;   // [DIDÁTICO] casa o MAC de destino exato
        }
        actions = {
            hit;
            @defaultonly miss;
        }
        const default_action = miss(0x1);    // [DIDÁTICO] se nada casar -> dropa
        size = 1024;
    }

    /* --- INSTANCIAÇÃO DOS REGISTRADORES (SRAM) ---
       Criamos 4 arrays independentes de tamanho 1, armazenando 32 bits cada,
       indexados por uma chave de 1 bit (posição 0).
    */
    // [DIDÁTICO] Register = memória PERSISTENTE (sobrevive entre pacotes, como um
    // `static` em C). São 4 porque: (1) cada registrador guarda no máx. 32 bits e
    // o token tem 128 -> 128/32 = 4; e (2) um registrador só pode ser acessado
    // uma vez por pacote. Foi a dica do enunciado: "utilize múltiplos registradores".
    Register<bit<32>, bit<1>>(1) secret_reg1;
    Register<bit<32>, bit<1>>(1) secret_reg2;
    Register<bit<32>, bit<1>>(1) secret_reg3;
    Register<bit<32>, bit<1>>(1) secret_reg4;

    apply {
        /* LÓGICA DO TÚNEL SECRETO (Default Deny / Bloqueio Padrão) */
        // [DIDÁTICO] O `apply` roda 1x por pacote. Note a mudança-chave em relação
        // ao esqueleto do professor: antes, forward.apply() era a 1a linha (roteava
        // tudo). Agora o roteamento só acontece LÁ NO FUNDO, depois de validar o
        // token. Em uma frase: "primeiro prove quem você é, depois eu te roteio".

        if (hdr.ethernet.ether_type == 0x9000) {
            /* FLUXO A: Gravação */
            // [DIDÁTICO] Fatiamos os 128 bits do token em 4 pedaços de 32 bits
            // (notação [alto:baixo]) e gravamos cada um num registrador. A partir
            // daqui o switch "lembra" o token entre pacotes.
            secret_reg1.write((bit<1>)0, hdr.secret.token[31:0]);
            secret_reg2.write((bit<1>)0, hdr.secret.token[63:32]);
            secret_reg3.write((bit<1>)0, hdr.secret.token[95:64]);
            secret_reg4.write((bit<1>)0, hdr.secret.token[127:96]);

            ig_dprsr_md.drop_ctl = 1;   // [DIDÁTICO] pacote de config não segue adiante
        }
        else if (hdr.ethernet.ether_type == 0x9001) {
            /* FLUXO B: Validação */
            // [DIDÁTICO] Lê os 4 registradores para o rascunho (meta). Cada read é
            // chamado UMA vez por registrador -> respeita a regra do hardware.
            meta.aux1 = secret_reg1.read((bit<1>)0);
            meta.aux2 = secret_reg2.read((bit<1>)0);
            meta.aux3 = secret_reg3.read((bit<1>)0);
            meta.aux4 = secret_reg4.read((bit<1>)0);

            /* Aninhamento Sequencial Seguro
               Isso evita o erro de 'condition too complex' do compilador
               e obriga o chip a validar as 4 fatias antes de qualquer coisa.
            */
            // [DIDÁTICO] Equivale a "if (a==r1 && b==r2 && c==r3 && d==r4)", mas
            // esse && quádruplo estoura a capacidade de um estágio do pipeline e o
            // p4c recusa. Aninhar os ifs dá o mesmo resultado e compila.
            if (hdr.secret.token[31:0] == meta.aux1) {
                if (hdr.secret.token[63:32] == meta.aux2) {
                    if (hdr.secret.token[95:64] == meta.aux3) {
                        if (hdr.secret.token[127:96] == meta.aux4) {

                            /* SUCESSO ABSOLUTO: O pacote provou ser autêntico.
                               Só agora ele ganha o direito de acessar a tabela de roteamento! */
                            // [DIDÁTICO] forward.apply() consulta a tabela de
                            // roteamento, que define a porta de saída (ou dropa).
                            forward.apply();

                        } else { ig_dprsr_md.drop_ctl = 1; }  // 4o pedaço difere -> dropa
                    } else { ig_dprsr_md.drop_ctl = 1; }      // 3o pedaço difere -> dropa
                } else { ig_dprsr_md.drop_ctl = 1; }          // 2o pedaço difere -> dropa
            } else { ig_dprsr_md.drop_ctl = 1; }              // 1o pedaço difere -> dropa
        }
        else {
            /* Qualquer outro tipo de pacote é sumariamente destruído */
            // [DIDÁTICO] "nega por padrão": o que não fala o protocolo do túnel não passa.
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
    // [DIDÁTICO] Toda a decisão foi tomada no Ingress; a saída não tem nada a
    // fazer além de deixar o deparser remontar o pacote. Por isso o apply é vazio.
    apply {}
}

/* ===================================================== Final Pipeline ===================================================== */
// [DIDÁTICO] Aqui conectamos as 6 peças na ordem da esteira PISA (entrada: ler,
// decidir, remontar; saída: ler, decidir, remontar). Switch(pipe) main é o
// ponto de entrada do programa — o equivalente conceitual do `int main()` em C.
Pipeline(
    SwitchIngressParser(),
    SwitchIngress(),
    SwitchIngressDeparser(),
    SwitchEgressParser(),
    SwitchEgress(),
    SwitchEgressDeparser()
) pipe;

Switch(pipe) main;