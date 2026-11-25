#ifndef MEMORIA_H
#define MEMORIA_H

#include "config.h"

typedef struct {
    Algoritmo algoritmo;
    int valida[NUMERO_PAGINAS];
    unsigned int frame_da_pagina[NUMERO_PAGINAS];
    unsigned int pagina_do_frame[NUMERO_FRAMES];
    unsigned long long carregado_em[NUMERO_FRAMES];
    unsigned long long usado_em[NUMERO_FRAMES];
    unsigned long long relogio;
    unsigned long long faltas;
    unsigned int ocupados;
    signed char fisica[NUMERO_FRAMES * TAMANHO_PAGINA];
} Memoria;

void memoria_iniciar(Memoria *memoria, Algoritmo algoritmo);
unsigned int memoria_obter_frame(Memoria *memoria, unsigned int pagina, const signed char *backing, int *despejou, unsigned int *pagina_despejada);
void memoria_registrar_uso(Memoria *memoria, unsigned int frame);
signed char memoria_ler(const Memoria *memoria, unsigned int frame, unsigned int deslocamento);

#endif
