# VM_gsg4

Projetando uma Memoria Virtual (Implementacao 6), Infraestrutura de Software, CESAR School. Login: gsg4.

Simulador de memoria virtual em C: enderecos logicos de 16 bits, paginas de 256 bytes, 128 frames, TLB de 16 entradas e substituicao fifo ou lru.

Estado atual: o programa ainda so valida as entradas. A traducao dos enderecos entra no proximo commit.

## Compilar

    make
    make clean

## Executar

    ./vm addresses.txt lru fifo

Os tres argumentos sao o arquivo de enderecos, o algoritmo de pagina (fifo ou lru) e o algoritmo da TLB (fifo ou lru). Valem so minusculas.

O arquivo BACKING_STORE.bin precisa estar no diretorio onde o programa roda e ter exatamente 65536 bytes.

## Arquivo de enderecos

Um inteiro decimal por linha, de 0 a 65535, sem sinal. Zeros a esquerda sao aceitos. Espacos so no fim da linha. O fim de linha pode ser LF ou CRLF, e o da ultima linha e opcional. Linha em branco, arquivo vazio, byte nulo, qualquer outro caractere ou numero acima de 65535 e erro.

## Erros

O programa valida tudo antes de comecar. Em caso de erro escreve "erro: motivo" na saida de erro, termina com codigo 1 e nao cria nem altera o correct.txt. Erros de argumentos mostram tambem a linha de uso.

## Testes

    make test

Roda tests/testa_entradas.sh com o vm normal e com o vm compilado com AddressSanitizer e UBSan (make asan). Os arquivos do professor usados nos testes ficam em tests/dados.
