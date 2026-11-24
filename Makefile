CFLAGS = -Wall -Wextra -std=c11 -O2
ASAN_FLAGS = -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer
OBJETOS = vm.o entrada.o

.PHONY: all asan test clean

all: vm

vm: $(OBJETOS)
	$(CC) $(CFLAGS) -o $@ $(OBJETOS)

%.o: %.c entrada.h
	$(CC) $(CFLAGS) -c -o $@ $<

asan: vm_asan

vm_asan: vm.c entrada.c entrada.h
	$(CC) -Wall -Wextra -std=c11 $(ASAN_FLAGS) -o $@ vm.c entrada.c

test: vm vm_asan
	bash tests/testa_entradas.sh ./vm
	bash tests/testa_entradas.sh ./vm_asan

clean:
	rm -f vm vm_asan *.o
