# VM_gsg4

Simulador de memoria virtual em C (Implementacao 6, Infraestrutura de Software, CESAR School, login gsg4).

Compilar:

    make

Executar:

    ./vm addresses.txt lru fifo

Os argumentos sao o arquivo de enderecos, o algoritmo de pagina (fifo ou lru) e o algoritmo da TLB (fifo ou lru). O BACKING_STORE.bin precisa estar na pasta onde o programa roda. A saida vai para a saida padrao, uma linha por endereco.

Outros fluxos (o executavel continua sendo o vm):

    make FRAMES=256
    make NOTLB=1
    make NOTHREAD=1

Testes:

    make test

Limpar:

    make clean
