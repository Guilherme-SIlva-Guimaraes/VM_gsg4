#define _POSIX_C_SOURCE 200809L

#include "entrada.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

enum estado { INICIO, DIGITOS, ESPACOS, RETORNO };

static ssize_t ler(int fd, void *destino, size_t quantidade)
{
    ssize_t n;

    do {
        n = read(fd, destino, quantidade);
    } while (n < 0 && errno == EINTR);
    return n;
}

static int abrir_arquivo(const char *caminho, const char *rotulo, char *erro, size_t tamanho_erro)
{
    int fd;
    struct stat info;

    do {
        fd = open(caminho, O_RDONLY);
    } while (fd < 0 && errno == EINTR);
    if (fd < 0) {
        if (errno == ENOENT) {
            snprintf(erro, tamanho_erro, "%s: arquivo nao existe", rotulo);
        } else if (errno == EACCES) {
            snprintf(erro, tamanho_erro, "%s: sem permissao de leitura", rotulo);
        } else {
            snprintf(erro, tamanho_erro, "%s: nao foi possivel abrir (%s)", rotulo, strerror(errno));
        }
        return -1;
    }
    if (fstat(fd, &info) < 0) {
        snprintf(erro, tamanho_erro, "%s: nao foi possivel consultar o arquivo (%s)", rotulo, strerror(errno));
        close(fd);
        return -1;
    }
    if (S_ISDIR(info.st_mode)) {
        snprintf(erro, tamanho_erro, "%s: e um diretorio, nao um arquivo", rotulo);
        close(fd);
        return -1;
    }
    return fd;
}

static int anexar(uint16_t **dados, size_t *quantidade, size_t *capacidade, unsigned int valor)
{
    uint16_t *novo;
    size_t nova_capacidade;

    if (*quantidade == *capacidade) {
        if (*capacidade > SIZE_MAX / sizeof(uint16_t) / 2) {
            return -1;
        }
        nova_capacidade = *capacidade == 0 ? 1024 : *capacidade * 2;
        novo = realloc(*dados, nova_capacidade * sizeof(uint16_t));
        if (novo == NULL) {
            return -1;
        }
        *dados = novo;
        *capacidade = nova_capacidade;
    }
    (*dados)[*quantidade] = (uint16_t)valor;
    *quantidade += 1;
    return 0;
}

int carregar_enderecos(const char *caminho, ListaEnderecos *lista, char *erro, size_t tamanho_erro)
{
    const char *rotulo = "arquivo de enderecos";
    int fd = abrir_arquivo(caminho, rotulo, erro, tamanho_erro);
    uint16_t *dados = NULL;
    size_t quantidade = 0;
    size_t capacidade = 0;
    unsigned long long linha = 1;
    unsigned int valor = 0;
    enum estado estado = INICIO;
    unsigned char bloco[65536];
    char invalido[48];
    const char *motivo = NULL;
    ssize_t n;
    ssize_t i;

    if (fd < 0) {
        return -1;
    }
    for (;;) {
        n = ler(fd, bloco, sizeof bloco);
        if (n < 0) {
            snprintf(erro, tamanho_erro, "%s: erro de leitura (%s)", rotulo, strerror(errno));
            goto falha;
        }
        if (n == 0) {
            break;
        }
        for (i = 0; i < n; i++) {
            unsigned char c = bloco[i];

            if (c >= '0' && c <= '9') {
                if (estado == ESPACOS) {
                    motivo = "espaco no meio da linha";
                    goto falha_linha;
                }
                if (estado == RETORNO) {
                    motivo = "caractere \\r fora do fim da linha";
                    goto falha_linha;
                }
                valor = valor * 10u + (unsigned int)(c - '0');
                if (valor > ENDERECO_MAXIMO) {
                    motivo = "endereco acima de 65535";
                    goto falha_linha;
                }
                estado = DIGITOS;
            } else if (c == ' ') {
                if (estado == INICIO) {
                    motivo = "espaco no inicio da linha";
                    goto falha_linha;
                }
                if (estado == RETORNO) {
                    motivo = "caractere \\r fora do fim da linha";
                    goto falha_linha;
                }
                estado = ESPACOS;
            } else if (c == '\r') {
                if (estado == INICIO) {
                    motivo = "linha em branco ou caractere \\r no inicio da linha";
                    goto falha_linha;
                }
                if (estado == RETORNO) {
                    motivo = "caractere \\r fora do fim da linha";
                    goto falha_linha;
                }
                estado = RETORNO;
            } else if (c == '\n') {
                if (estado == INICIO) {
                    motivo = "linha em branco";
                    goto falha_linha;
                }
                if (anexar(&dados, &quantidade, &capacidade, valor) < 0) {
                    snprintf(erro, tamanho_erro, "%s: memoria insuficiente", rotulo);
                    goto falha;
                }
                valor = 0;
                estado = INICIO;
                linha++;
            } else if (c == '\0') {
                motivo = "byte nulo";
                goto falha_linha;
            } else {
                snprintf(invalido, sizeof invalido, "caractere invalido (0x%02X)", (unsigned int)c);
                motivo = invalido;
                goto falha_linha;
            }
        }
    }
    if (estado != INICIO) {
        if (anexar(&dados, &quantidade, &capacidade, valor) < 0) {
            snprintf(erro, tamanho_erro, "%s: memoria insuficiente", rotulo);
            goto falha;
        }
    }
    close(fd);
    if (quantidade == 0) {
        snprintf(erro, tamanho_erro, "%s: arquivo vazio", rotulo);
        free(dados);
        return -1;
    }
    lista->enderecos = dados;
    lista->quantidade = quantidade;
    return 0;

falha_linha:
    snprintf(erro, tamanho_erro, "%s: linha %llu: %s", rotulo, linha, motivo);
falha:
    free(dados);
    close(fd);
    return -1;
}

int carregar_backing(const char *caminho, signed char *destino, char *erro, size_t tamanho_erro)
{
    const char *rotulo = "BACKING_STORE.bin";
    int fd = abrir_arquivo(caminho, rotulo, erro, tamanho_erro);
    size_t total = 0;
    unsigned char sobra;
    ssize_t n = 0;

    if (fd < 0) {
        return -1;
    }
    while (total < TAMANHO_BACKING) {
        n = ler(fd, destino + total, TAMANHO_BACKING - total);
        if (n < 0) {
            goto falha_leitura;
        }
        if (n == 0) {
            break;
        }
        total += (size_t)n;
    }
    if (total == TAMANHO_BACKING) {
        n = ler(fd, &sobra, 1);
        if (n < 0) {
            goto falha_leitura;
        }
    }
    close(fd);
    if (total != TAMANHO_BACKING || n > 0) {
        snprintf(erro, tamanho_erro, "%s: tamanho invalido (esperado %zu bytes)", rotulo, (size_t)TAMANHO_BACKING);
        return -1;
    }
    return 0;

falha_leitura:
    snprintf(erro, tamanho_erro, "%s: erro de leitura (%s)", rotulo, strerror(errno));
    close(fd);
    return -1;
}

void liberar_enderecos(ListaEnderecos *lista)
{
    free(lista->enderecos);
    lista->enderecos = NULL;
    lista->quantidade = 0;
}
