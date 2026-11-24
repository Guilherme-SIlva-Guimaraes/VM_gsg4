#ifndef CONFIG_H
#define CONFIG_H

#include <stddef.h>

#ifndef NUMERO_FRAMES
#define NUMERO_FRAMES 128u
#endif

#define TAMANHO_PAGINA 256u
#define NUMERO_PAGINAS 256u
#define TAMANHO_TLB 16u
#define ENDERECO_MAXIMO 65535u
#define TAMANHO_BACKING ((size_t)TAMANHO_PAGINA * NUMERO_PAGINAS)

#ifdef SEM_TLB
#define COM_TLB 0
#else
#define COM_TLB 1
#endif

#ifdef SEM_THREAD
#define COM_THREAD 0
#else
#define COM_THREAD 1
#endif

typedef enum { ALG_FIFO, ALG_LRU } Algoritmo;

#endif
