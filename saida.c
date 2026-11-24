#define _POSIX_C_SOURCE 200809L

#include "saida.h"

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define NOME_FINAL "correct.txt"
#define MODELO "correct.txt.tmpXXXXXX"

static char temporario_atual[32];

static void tratar_sinal(int sinal)
{
    if (temporario_atual[0] != '\0') {
        unlink(temporario_atual);
    }
    signal(sinal, SIG_DFL);
    raise(sinal);
}

static void instalar_tratadores(void)
{
    struct sigaction acao;

    memset(&acao, 0, sizeof acao);
    acao.sa_handler = tratar_sinal;
    sigemptyset(&acao.sa_mask);
    sigaction(SIGINT, &acao, NULL);
    sigaction(SIGTERM, &acao, NULL);
    sigaction(SIGHUP, &acao, NULL);
}

int saida_abrir(Saida *saida, char *erro, size_t tamanho_erro)
{
    char modelo[] = MODELO;
    mode_t mascara;
    int fd = mkstemp(modelo);

    if (fd < 0) {
        snprintf(erro, tamanho_erro, "nao foi possivel criar o arquivo temporario no diretorio atual (%s)", strerror(errno));
        return -1;
    }
    mascara = umask(0);
    umask(mascara);
    if (fchmod(fd, (mode_t)(0666 & ~mascara)) < 0) {
        snprintf(erro, tamanho_erro, "nao foi possivel ajustar as permissoes do arquivo temporario (%s)", strerror(errno));
        close(fd);
        unlink(modelo);
        return -1;
    }
    saida->arquivo = fdopen(fd, "w");
    if (saida->arquivo == NULL) {
        snprintf(erro, tamanho_erro, "nao foi possivel abrir o arquivo temporario (%s)", strerror(errno));
        close(fd);
        unlink(modelo);
        return -1;
    }
    memcpy(saida->temporario, modelo, sizeof modelo);
    memcpy(temporario_atual, modelo, sizeof modelo);
    instalar_tratadores();
    return 0;
}

int saida_confirmar(Saida *saida, char *erro, size_t tamanho_erro)
{
    int codigo = 0;

    if (fflush(saida->arquivo) != 0) {
        codigo = errno;
    }
    if (ferror(saida->arquivo) && codigo == 0) {
        codigo = EIO;
    }
    if (fclose(saida->arquivo) != 0 && codigo == 0) {
        codigo = errno;
    }
    saida->arquivo = NULL;
    if (codigo != 0) {
        snprintf(erro, tamanho_erro, "falha ao gravar o arquivo de saida (%s)", strerror(codigo));
        unlink(saida->temporario);
        temporario_atual[0] = '\0';
        return -1;
    }
    if (rename(saida->temporario, NOME_FINAL) < 0) {
        codigo = errno;
        snprintf(erro, tamanho_erro, "nao foi possivel gravar %s (%s)", NOME_FINAL, strerror(codigo));
        unlink(saida->temporario);
        temporario_atual[0] = '\0';
        return -1;
    }
    temporario_atual[0] = '\0';
    return 0;
}

void saida_cancelar(Saida *saida)
{
    if (saida->arquivo != NULL) {
        fclose(saida->arquivo);
        saida->arquivo = NULL;
    }
    unlink(saida->temporario);
    temporario_atual[0] = '\0';
}
