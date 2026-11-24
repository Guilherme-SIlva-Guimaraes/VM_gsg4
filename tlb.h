#ifndef TLB_H
#define TLB_H

#include "config.h"

typedef struct {
    int valida;
    unsigned int pagina;
    unsigned int frame;
    unsigned long long usado_em;
} EntradaTlb;

typedef struct {
    EntradaTlb entradas[TAMANHO_TLB];
    Algoritmo algoritmo;
    unsigned int proximo;
    unsigned long long relogio;
} Tlb;

void tlb_iniciar(Tlb *tlb, Algoritmo algoritmo);
int tlb_buscar(Tlb *tlb, unsigned int pagina, unsigned int *slot, unsigned int *frame, int *codigo_erro);
unsigned int tlb_inserir(Tlb *tlb, unsigned int pagina, unsigned int frame);
void tlb_invalidar(Tlb *tlb, unsigned int pagina);

#endif
