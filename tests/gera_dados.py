import os
import random
import sys

SEMENTE = 20261124


def byte_do_backing(i):
    return ((i // 256) * 5 + (i % 256) * 3 + 1) % 256


def main():
    destino = sys.argv[1]
    os.makedirs(destino, exist_ok=True)
    with open(os.path.join(destino, "BACKING_STORE.bin"), "wb") as arquivo:
        arquivo.write(bytes(byte_do_backing(i) for i in range(65536)))
    rng = random.Random(SEMENTE)
    paginas = list(range(256))
    rng.shuffle(paginas)
    usadas = paginas[:200]
    recentes = []
    with open(os.path.join(destino, "addresses.txt"), "w", newline="\n") as arquivo:
        for _ in range(1000):
            if recentes and rng.random() < 0.35:
                pagina = rng.choice(recentes[-12:])
            else:
                pagina = rng.choice(usadas)
            recentes.append(pagina)
            arquivo.write("%d\n" % (pagina * 256 + rng.randrange(256)))


main()
