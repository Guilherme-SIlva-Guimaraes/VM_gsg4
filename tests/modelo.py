import sys
from collections import OrderedDict

TAMANHO_TLB = 16


def ler_enderecos(caminho):
    enderecos = []
    with open(caminho) as arquivo:
        for linha in arquivo:
            linha = linha.strip()
            if linha:
                enderecos.append(int(linha))
    return enderecos


def ler_backing(caminho):
    with open(caminho, "rb") as arquivo:
        dados = arquivo.read()
    return [b - 256 if b > 127 else b for b in dados]


def simular(enderecos, backing, algoritmo_pagina, algoritmo_tlb, frames, com_tlb):
    tlb = [None] * TAMANHO_TLB
    ordem_tlb = OrderedDict()
    recencia_tlb = OrderedDict()
    memoria = OrderedDict()
    proximo_frame = 0
    linhas = []
    faltas = 0
    acertos = 0
    for endereco in enderecos:
        pagina = endereco >> 8
        deslocamento = endereco & 255
        slot = None
        frame = None
        if com_tlb:
            for i, entrada in enumerate(tlb):
                if entrada is not None and entrada[0] == pagina:
                    slot = i
                    frame = entrada[1]
                    break
        if slot is not None:
            acertos += 1
            recencia_tlb.move_to_end(slot)
            if algoritmo_pagina == "lru":
                memoria.move_to_end(pagina)
        else:
            if pagina in memoria:
                frame = memoria[pagina]
                if algoritmo_pagina == "lru":
                    memoria.move_to_end(pagina)
            else:
                faltas += 1
                if proximo_frame < frames:
                    frame = proximo_frame
                    proximo_frame += 1
                else:
                    vitima = next(iter(memoria))
                    frame = memoria.pop(vitima)
                    for i, entrada in enumerate(tlb):
                        if entrada is not None and entrada[0] == vitima:
                            tlb[i] = None
                            ordem_tlb.pop(i, None)
                            recencia_tlb.pop(i, None)
                memoria[pagina] = frame
            if com_tlb:
                livres = [i for i, entrada in enumerate(tlb) if entrada is None]
                if livres:
                    slot = livres[0]
                elif algoritmo_tlb == "fifo":
                    slot = next(iter(ordem_tlb))
                else:
                    slot = next(iter(recencia_tlb))
                tlb[slot] = (pagina, frame)
                ordem_tlb.pop(slot, None)
                ordem_tlb[slot] = True
                recencia_tlb.pop(slot, None)
                recencia_tlb[slot] = True
        valor = backing[endereco]
        fisico = frame * 256 + deslocamento
        if com_tlb:
            linhas.append("Virtual address: %d TLB: %d Physical address: %d Value: %d" % (endereco, slot, fisico, valor))
        else:
            linhas.append("Virtual address: %d Physical address: %d Value: %d" % (endereco, fisico, valor))
    return linhas, faltas, acertos


def main():
    enderecos = ler_enderecos(sys.argv[1])
    backing = ler_backing(sys.argv[2])
    com_tlb = sys.argv[6] == "tlb"
    linhas, faltas, acertos = simular(enderecos, backing, sys.argv[3], sys.argv[4], int(sys.argv[5]), com_tlb)
    if len(sys.argv) > 7 and sys.argv[7] == "arquivo":
        total = len(enderecos)
        linhas.append("Number of Translated Addresses = %d" % total)
        linhas.append("Page Faults = %d" % faltas)
        linhas.append("Page Fault Rate = %.3f" % (faltas / total))
        if com_tlb:
            linhas.append("TLB Hits = %d" % acertos)
            linhas.append("TLB Hit Rate = %.3f" % (acertos / total))
    sys.stdout.write("\n".join(linhas) + "\n")


main()
