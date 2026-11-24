FRAMES ?= 128
NOTLB ?=
NOTHREAD ?=

ifeq ($(filter $(FRAMES),128 256),)
$(error FRAMES deve ser 128 ou 256)
endif
ifneq ($(filter-out 1,$(NOTLB)),)
$(error NOTLB deve ser 1 ou ficar vazio)
endif
ifneq ($(filter-out 1,$(NOTHREAD)),)
$(error NOTHREAD deve ser 1 ou ficar vazio)
endif

DEFS = -DNUMERO_FRAMES=$(FRAMES)u
ifeq ($(NOTLB),1)
DEFS += -DSEM_TLB
endif
ifeq ($(NOTHREAD),1)
DEFS += -DSEM_THREAD
endif

CFLAGS = -Wall -Wextra -std=c11 -O2 -pthread $(DEFS)
ASAN_FLAGS = -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer
FONTES = vm.c entrada.c memoria.c tlb.c simulador.c saida.c
OBJETOS = $(FONTES:.c=.o)
CABECALHOS = config.h entrada.h memoria.h tlb.h simulador.h saida.h
CONFIG = FRAMES=$(FRAMES) NOTLB=$(NOTLB) NOTHREAD=$(NOTHREAD)

.PHONY: all asan test clean FORCE

all: vm

.config: FORCE
	@echo '$(CONFIG)' | cmp -s - $@ || echo '$(CONFIG)' > $@

FORCE:

vm: $(OBJETOS)
	$(CC) $(CFLAGS) -o $@ $(OBJETOS)

%.o: %.c $(CABECALHOS) .config
	$(CC) $(CFLAGS) -c -o $@ $<

asan: vm_asan

vm_asan: $(FONTES) $(CABECALHOS) .config
	$(CC) -Wall -Wextra -std=c11 -pthread $(DEFS) $(ASAN_FLAGS) -o $@ $(FONTES)

test: vm vm_asan
	bash tests/testa_entradas.sh ./vm
	bash tests/testa_entradas.sh ./vm_asan
	bash tests/testa_saida.sh ./vm
	bash tests/testa_saida.sh ./vm_asan
	bash tests/testa_modos.sh

clean:
	rm -f vm vm_asan *.o .config
