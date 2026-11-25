#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "entrada.h"
#include "simulador.h"

#define USO "uso: ./vm arquivo_enderecos fifo|lru fifo|lru"

static int algoritmo_valido(const char *texto)
{
    return strcmp(texto, "fifo") == 0 || strcmp(texto, "lru") == 0;
}

static Algoritmo converter_algoritmo(const char *texto)
{
    return strcmp(texto, "lru") == 0 ? ALG_LRU : ALG_FIFO;
}

static void copiar_seguro(const char *texto, char *destino, size_t tamanho)
{
    size_t i;

    for (i = 0; i + 1 < tamanho && texto[i] != '\0'; i++) {
        unsigned char c = (unsigned char)texto[i];

        destino[i] = (c >= 32 && c < 127) ? (char)c : '?';
    }
    destino[i] = '\0';
}

static int erro_algoritmo(const char *rotulo, const char *valor)
{
    char seguro[40];

    copiar_seguro(valor, seguro, sizeof seguro);
    fprintf(stderr, "erro: algoritmo %s invalido '%s' (use fifo ou lru)\n", rotulo, seguro);
    fprintf(stderr, "%s\n", USO);
    return 1;
}

int main(int argc, char **argv)
{
    char erro[512];
    signed char backing[TAMANHO_BACKING];
    ListaEnderecos lista = {NULL, 0};
    char *texto = NULL;
    size_t tamanho = 0;
    FILE *buffer;
    int status;

    if (argc != 4) {
        fprintf(stderr, "erro: numero de argumentos invalido (esperado 3, recebido %d)\n", argc > 0 ? argc - 1 : 0);
        fprintf(stderr, "%s\n", USO);
        return 1;
    }
    if (!algoritmo_valido(argv[2])) {
        return erro_algoritmo("de pagina", argv[2]);
    }
    if (!algoritmo_valido(argv[3])) {
        return erro_algoritmo("da TLB", argv[3]);
    }
    if (carregar_enderecos(argv[1], &lista, erro, sizeof erro) < 0) {
        fprintf(stderr, "erro: %s\n", erro);
        return 1;
    }
    if (carregar_backing("BACKING_STORE.bin", backing, erro, sizeof erro) < 0) {
        liberar_enderecos(&lista);
        fprintf(stderr, "erro: %s\n", erro);
        return 1;
    }
    buffer = open_memstream(&texto, &tamanho);
    if (buffer == NULL) {
        liberar_enderecos(&lista);
        fprintf(stderr, "erro: sem memoria para montar a saida\n");
        return 1;
    }
    status = simular(&lista, backing, converter_algoritmo(argv[2]), converter_algoritmo(argv[3]), buffer, erro, sizeof erro);
    liberar_enderecos(&lista);
    if (fclose(buffer) != 0 && status == 0) {
        snprintf(erro, sizeof erro, "falha ao montar a saida em memoria");
        status = -1;
    }
    if (status < 0) {
        free(texto);
        fprintf(stderr, "erro: %s\n", erro);
        return 1;
    }
    if (fwrite(texto, 1, tamanho, stdout) != tamanho || fflush(stdout) != 0) {
        free(texto);
        fprintf(stderr, "erro: falha ao escrever a saida\n");
        return 1;
    }
    free(texto);
    return 0;
}
