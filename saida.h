#ifndef SAIDA_H
#define SAIDA_H

#include <stddef.h>
#include <stdio.h>

typedef struct {
    FILE *arquivo;
    char temporario[32];
} Saida;

int saida_abrir(Saida *saida, char *erro, size_t tamanho_erro);
int saida_confirmar(Saida *saida, char *erro, size_t tamanho_erro);
void saida_cancelar(Saida *saida);

#endif
