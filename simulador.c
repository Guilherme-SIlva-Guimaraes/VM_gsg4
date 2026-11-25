#define _POSIX_C_SOURCE 200809L

#include "simulador.h"

#include <stdio.h>
#include <string.h>

#include "memoria.h"
#include "tlb.h"

int simular(const ListaEnderecos *lista, const signed char *backing, Algoritmo algoritmo_pagina, Algoritmo algoritmo_tlb, FILE *saida, char *erro, size_t tamanho_erro)
{
    Memoria memoria;
    Tlb tlb;
    size_t i;

    memoria_iniciar(&memoria, algoritmo_pagina);
    tlb_iniciar(&tlb, algoritmo_tlb);
    for (i = 0; i < lista->quantidade; i++) {
        unsigned int endereco = lista->enderecos[i];
        unsigned int pagina = endereco / TAMANHO_PAGINA;
        unsigned int deslocamento = endereco % TAMANHO_PAGINA;
        unsigned int frame = 0;
        unsigned int slot = 0;
        int achou = 0;
        int codigo = 0;

        if (COM_TLB) {
            achou = tlb_buscar(&tlb, pagina, &slot, &frame, &codigo);
            if (achou < 0) {
                snprintf(erro, tamanho_erro, "nao foi possivel criar thread da TLB (%s)", strerror(codigo));
                return -1;
            }
        }
        if (achou) {
            memoria_registrar_uso(&memoria, frame);
        } else {
            int despejou;
            unsigned int despejada;

            frame = memoria_obter_frame(&memoria, pagina, backing, &despejou, &despejada);
            if (COM_TLB) {
                if (despejou) {
                    tlb_invalidar(&tlb, despejada);
                }
                slot = tlb_inserir(&tlb, pagina, frame);
            }
        }
        if (COM_TLB) {
            fprintf(saida, "Virtual address: %u TLB: %u Physical address: %u Value: %d\n", endereco, slot, frame * TAMANHO_PAGINA + deslocamento, (int)memoria_ler(&memoria, frame, deslocamento));
        } else {
            fprintf(saida, "Virtual address: %u Physical address: %u Value: %d\n", endereco, frame * TAMANHO_PAGINA + deslocamento, (int)memoria_ler(&memoria, frame, deslocamento));
        }
    }
    if (ferror(saida)) {
        snprintf(erro, tamanho_erro, "falha ao escrever a saida");
        return -1;
    }
    return 0;
}
