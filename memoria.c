#define _POSIX_C_SOURCE 200809L

#include "memoria.h"

#include <string.h>

void memoria_iniciar(Memoria *memoria, Algoritmo algoritmo)
{
    memset(memoria, 0, sizeof *memoria);
    memoria->algoritmo = algoritmo;
}

static unsigned int escolher_vitima(const Memoria *memoria)
{
    const unsigned long long *chave = memoria->algoritmo == ALG_LRU ? memoria->usado_em : memoria->carregado_em;
    unsigned int melhor = 0;
    unsigned int i;

    for (i = 1; i < NUMERO_FRAMES; i++) {
        if (chave[i] < chave[melhor]) {
            melhor = i;
        }
    }
    return melhor;
}

unsigned int memoria_obter_frame(Memoria *memoria, unsigned int pagina, const signed char *backing, int *despejou, unsigned int *pagina_despejada)
{
    unsigned int frame;

    *despejou = 0;
    *pagina_despejada = 0;
    if (memoria->valida[pagina]) {
        frame = memoria->frame_da_pagina[pagina];
        memoria->relogio += 1;
        memoria->usado_em[frame] = memoria->relogio;
        return frame;
    }
    memoria->faltas += 1;
    if (memoria->ocupados < NUMERO_FRAMES) {
        frame = memoria->ocupados;
        memoria->ocupados += 1;
    } else {
        frame = escolher_vitima(memoria);
        *pagina_despejada = memoria->pagina_do_frame[frame];
        memoria->valida[*pagina_despejada] = 0;
        *despejou = 1;
    }
    memcpy(&memoria->fisica[(size_t)frame * TAMANHO_PAGINA], &backing[(size_t)pagina * TAMANHO_PAGINA], TAMANHO_PAGINA);
    memoria->valida[pagina] = 1;
    memoria->frame_da_pagina[pagina] = frame;
    memoria->pagina_do_frame[frame] = pagina;
    memoria->relogio += 1;
    memoria->carregado_em[frame] = memoria->relogio;
    memoria->usado_em[frame] = memoria->relogio;
    return frame;
}

void memoria_registrar_uso(Memoria *memoria, unsigned int frame)
{
    memoria->relogio += 1;
    memoria->usado_em[frame] = memoria->relogio;
}

signed char memoria_ler(const Memoria *memoria, unsigned int frame, unsigned int deslocamento)
{
    return memoria->fisica[(size_t)frame * TAMANHO_PAGINA + deslocamento];
}
