#define _POSIX_C_SOURCE 200809L

#include "tlb.h"

#include <pthread.h>
#include <string.h>

typedef struct {
    const EntradaTlb *entrada;
    unsigned int pagina;
    int achou;
} Busca;

static void *buscar_entrada(void *dados)
{
    Busca *busca = dados;

    busca->achou = busca->entrada->valida && busca->entrada->pagina == busca->pagina;
    return NULL;
}

void tlb_iniciar(Tlb *tlb, Algoritmo algoritmo)
{
    memset(tlb, 0, sizeof *tlb);
    tlb->algoritmo = algoritmo;
}

int tlb_buscar(Tlb *tlb, unsigned int pagina, unsigned int *slot, unsigned int *frame, int *codigo_erro)
{
    Busca buscas[TAMANHO_TLB];
    pthread_t threads[TAMANHO_TLB];
    unsigned int criadas = 0;
    unsigned int i;
    int rc;
    int falhou = 0;

    for (i = 0; i < TAMANHO_TLB; i++) {
        buscas[i].entrada = &tlb->entradas[i];
        buscas[i].pagina = pagina;
        buscas[i].achou = 0;
    }
    if (COM_THREAD) {
        for (i = 0; i < TAMANHO_TLB; i++) {
            rc = pthread_create(&threads[i], NULL, buscar_entrada, &buscas[i]);
            if (rc != 0) {
                *codigo_erro = rc;
                falhou = 1;
                break;
            }
            criadas += 1;
        }
        for (i = 0; i < criadas; i++) {
            pthread_join(threads[i], NULL);
        }
        if (falhou) {
            return -1;
        }
    } else {
        for (i = 0; i < TAMANHO_TLB; i++) {
            buscar_entrada(&buscas[i]);
        }
    }
    for (i = 0; i < TAMANHO_TLB; i++) {
        if (buscas[i].achou) {
            *slot = i;
            *frame = tlb->entradas[i].frame;
            if (tlb->algoritmo == ALG_LRU) {
                tlb->relogio += 1;
                tlb->entradas[i].usado_em = tlb->relogio;
            }
            return 1;
        }
    }
    return 0;
}

static unsigned int escolher_lru(const Tlb *tlb)
{
    unsigned int melhor = 0;
    unsigned int i;

    for (i = 0; i < TAMANHO_TLB; i++) {
        if (!tlb->entradas[i].valida) {
            return i;
        }
        if (tlb->entradas[i].usado_em < tlb->entradas[melhor].usado_em) {
            melhor = i;
        }
    }
    return melhor;
}

unsigned int tlb_inserir(Tlb *tlb, unsigned int pagina, unsigned int frame)
{
    unsigned int slot;

    if (tlb->algoritmo == ALG_FIFO) {
        slot = tlb->proximo;
        tlb->proximo = (tlb->proximo + 1) % TAMANHO_TLB;
    } else {
        slot = escolher_lru(tlb);
    }
    tlb->relogio += 1;
    tlb->entradas[slot].valida = 1;
    tlb->entradas[slot].pagina = pagina;
    tlb->entradas[slot].frame = frame;
    tlb->entradas[slot].usado_em = tlb->relogio;
    return slot;
}

void tlb_invalidar(Tlb *tlb, unsigned int pagina)
{
    unsigned int i;

    for (i = 0; i < TAMANHO_TLB; i++) {
        if (tlb->entradas[i].valida && tlb->entradas[i].pagina == pagina) {
            tlb->entradas[i].valida = 0;
        }
    }
}
