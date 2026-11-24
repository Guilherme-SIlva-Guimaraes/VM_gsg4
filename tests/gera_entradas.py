import os
import random
import sys


def escrever(pasta, nome, enderecos):
    with open(os.path.join(pasta, nome + ".txt"), "w", newline="\n") as arquivo:
        for endereco in enderecos:
            arquivo.write("%d\n" % endereco)


def com_deslocamento(rng, pagina):
    return pagina * 256 + rng.randrange(256)


def localidade(rng, quantidade, tamanho_conjunto, salto):
    conjunto = rng.sample(range(256), tamanho_conjunto)
    enderecos = []
    for _ in range(quantidade):
        if rng.random() < salto:
            conjunto[rng.randrange(tamanho_conjunto)] = rng.randrange(256)
        enderecos.append(com_deslocamento(rng, rng.choice(conjunto)))
    return enderecos


def main():
    pasta = sys.argv[1]
    os.makedirs(pasta, exist_ok=True)
    rng = random.Random(20261124)
    escrever(pasta, "um_zero", [0])
    escrever(pasta, "um_maximo", [65535])
    escrever(pasta, "repetido", [4660] * 300)
    escrever(pasta, "sequencial_128", [p * 256 for p in range(128)])
    escrever(pasta, "sequencial_129", [p * 256 + 1 for p in range(129)])
    escrever(pasta, "ciclico_129", [(i % 129) * 256 + (i % 7) for i in range(774)])
    escrever(pasta, "todas_256_ida_e_volta", [com_deslocamento(rng, p) for p in list(range(256)) + list(range(255, -1, -1))])
    escrever(pasta, "aleatorio_50", [rng.randrange(65536) for _ in range(50)])
    escrever(pasta, "aleatorio_1000_a", [rng.randrange(65536) for _ in range(1000)])
    escrever(pasta, "aleatorio_1000_b", [rng.randrange(65536) for _ in range(1000)])
    escrever(pasta, "localidade_20_paginas", localidade(rng, 3000, 20, 0.05))
    escrever(pasta, "localidade_140_paginas", localidade(rng, 6000, 140, 0.02))
    escrever(pasta, "aleatorio_20000", [rng.randrange(65536) for _ in range(20000)])
    escrever(pasta, "localidade_100000", localidade(rng, 100000, 100, 0.01))


main()
