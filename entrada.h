#ifndef ENTRADA_H
#define ENTRADA_H

#include <stddef.h>
#include <stdint.h>

#define TAMANHO_PAGINA 256u
#define NUMERO_PAGINAS 256u
#define TAMANHO_BACKING ((size_t)TAMANHO_PAGINA * NUMERO_PAGINAS)
#define ENDERECO_MAXIMO 65535u

typedef struct {
    uint16_t *enderecos;
    size_t quantidade;
} ListaEnderecos;

int carregar_enderecos(const char *caminho, ListaEnderecos *lista, char *erro, size_t tamanho_erro);
int carregar_backing(const char *caminho, signed char *destino, char *erro, size_t tamanho_erro);
void liberar_enderecos(ListaEnderecos *lista);

#endif
