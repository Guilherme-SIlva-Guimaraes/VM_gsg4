#ifndef SIMULADOR_H
#define SIMULADOR_H

#include <stddef.h>
#include <stdio.h>

#include "config.h"
#include "entrada.h"

int simular(const ListaEnderecos *lista, const signed char *backing, Algoritmo algoritmo_pagina, Algoritmo algoritmo_tlb, FILE *saida, char *erro, size_t tamanho_erro);

#endif
