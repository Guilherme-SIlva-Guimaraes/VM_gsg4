#ifndef SIMULADOR_H
#define SIMULADOR_H

#include <stddef.h>
#include <stdio.h>

#include "config.h"
#include "entrada.h"

typedef struct {
    size_t enderecos;
    unsigned long long faltas;
    unsigned long long acertos_tlb;
} Estatisticas;

int simular(const ListaEnderecos *lista, const signed char *backing, Algoritmo algoritmo_pagina, Algoritmo algoritmo_tlb, FILE *saida, Estatisticas *estatisticas, char *erro, size_t tamanho_erro);
void escrever_estatisticas(FILE *arquivo, const Estatisticas *estatisticas);

#endif
