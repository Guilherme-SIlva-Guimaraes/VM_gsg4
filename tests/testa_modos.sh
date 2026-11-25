RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/vmmodos.XXXXXX)
DADOS="$TMP/dados"
SAIDAS="$TMP/saidas"
FONTES="Makefile config.h entrada.c entrada.h memoria.c memoria.h simulador.c simulador.h tlb.c tlb.h vm.c"
OK=0
FALHOU=0
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$SAIDAS"

passou() { OK=$((OK + 1)); echo "OK      $1"; }
falhou() { FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 ($2)"; }

python3 -I "$RAIZ/tests/gera_dados.py" "$DADOS"
DISTINTAS=$(awk '{ p[int($1 / 256)] = 1 } END { n = 0; for (k in p) n++; print n }' "$DADOS/addresses.txt")
awk 'BEGIN { for (i = 0; i < 100000; i++) print i % 65536 }' > "$TMP/grande.txt"

coluna_pa() { awk '/^Virtual address:/ { print $(NF - 2) }' "$1"; }

copia_fontes() {
    rm -rf "$1"
    mkdir -p "$1"
    for f in $FONTES; do
        cp "$RAIZ/$f" "$1/$f"
    done
}

roda() {
    local bin=$1
    local destino=$2
    local pag=$3
    local tlb=$4
    local entrada=${5:-$DADOS/addresses.txt}
    local w="$TMP/w"
    rm -rf "$w"
    mkdir -p "$w"
    cp "$DADOS/BACKING_STORE.bin" "$w/"
    cp "$entrada" "$w/addresses.txt"
    ( cd "$w" && "$bin" addresses.txt "$pag" "$tlb" ) > "$destino" 2> "$TMP/erro"
    COD=$?
    ARQUIVOS=$(ls -A "$w" | sort | tr '\n' ' ')
}

confere() {
    local nome=$1
    local arq=$2
    local frames=$3
    local com_tlb=$4
    local res
    if [ "$COD" -ne 0 ]; then
        falhou "$nome" "codigo $COD: $(head -c 160 "$TMP/erro" | tr '\n' ' ')"
        return
    fi
    if [ -s "$TMP/erro" ]; then
        falhou "$nome" "stderr nao vazio"
        return
    fi
    if [ "$ARQUIVOS" != "BACKING_STORE.bin addresses.txt " ]; then
        falhou "$nome" "arquivos no diretorio: $ARQUIVOS"
        return
    fi
    if [ "$(wc -l < "$arq")" -ne 1000 ]; then
        falhou "$nome" "$(wc -l < "$arq") linhas, esperado 1000"
        return
    fi
    if grep -q -v '^Virtual address:' "$arq"; then
        falhou "$nome" "linha que nao e de endereco na saida"
        return
    fi
    res=$(awk -v frames="$frames" -v com_tlb="$com_tlb" '
FNR == NR { ender[FNR] = $1; total = FNR; next }
/^Virtual address:/ {
    k++
    va = $3
    pa = $(NF - 2)
    if (va != ender[k]) erro = erro " va" k
    if (pa % 256 != va % 256) erro = erro " deslocamento" k
    esperado = (int(va / 256) * 5 + (va % 256) * 3 + 1) % 256
    if (esperado > 127) esperado -= 256
    if ($NF != esperado) erro = erro " valor" k
    fr = int(pa / 256)
    if (fr >= frames) erro = erro " frame" k
    pagina = int(va / 256)
    if (!(pagina in visto)) {
        visto[pagina] = 1
        distintas++
        if (distintas <= frames && fr != distintas - 1) erro = erro " ordem_dos_frames" k
    }
    if (frames == 256) {
        if ((pagina in frame_de) && frame_de[pagina] != fr) erro = erro " frame_muda" k
        if ((fr in pagina_de) && pagina_de[fr] != pagina) erro = erro " frame_repetido" k
        frame_de[pagina] = fr
        pagina_de[fr] = pagina
    }
    if (com_tlb == 1 && ($5 < 0 || $5 > 15)) erro = erro " slot" k
}
END {
    if (k != total) erro = erro " linhas" k
    if (erro == "") print "ok"; else print erro
}' "$DADOS/addresses.txt" "$arq")
    if [ "$res" != ok ]; then
        falhou "$nome" "invariantes:$res"
        return
    fi
    passou "$nome"
}

for frames in 128 256; do
    for notlb in "" 1; do
        for nothread in "" 1; do
            nome="frames${frames}_notlb${notlb:-0}_nothread${nothread:-0}"
            dir="$TMP/$nome"
            copia_fontes "$dir"
            make -C "$dir" FRAMES=$frames NOTLB=$notlb NOTHREAD=$nothread vm vm_asan > "$dir/make.log" 2>&1
            cod=$?
            if [ "$cod" -ne 0 ]; then
                falhou "compila_$nome" "make saiu com $cod: $(tail -n 3 "$dir/make.log" | tr '\n' ' ')"
                continue
            fi
            if grep -q -i warning "$dir/make.log"; then
                falhou "compila_$nome" "make mostrou warning: $(grep -i -m 1 warning "$dir/make.log")"
                continue
            fi
            passou "compila_$nome"
            if [ -n "$notlb" ]; then
                com_tlb=0
            else
                com_tlb=1
            fi
            for pag in fifo lru; do
                for tlb in fifo lru; do
                    roda "$dir/vm" "$SAIDAS/${nome}_${pag}_${tlb}.txt" $pag $tlb
                    confere "${nome}_${pag}_${tlb}" "$SAIDAS/${nome}_${pag}_${tlb}.txt" $frames $com_tlb
                done
            done
            for combo in "lru fifo" "fifo lru"; do
                pag=${combo% *}
                tlb=${combo#* }
                roda "$dir/vm_asan" "$SAIDAS/${nome}_asan_${pag}_${tlb}.txt" $pag $tlb
                confere "${nome}_asan_${pag}_${tlb}" "$SAIDAS/${nome}_asan_${pag}_${tlb}.txt" $frames $com_tlb
                if cmp -s "$SAIDAS/${nome}_asan_${pag}_${tlb}.txt" "$SAIDAS/${nome}_${pag}_${tlb}.txt"; then
                    passou "${nome}_asan_igual_ao_normal_${pag}_${tlb}"
                else
                    falhou "${nome}_asan_igual_ao_normal_${pag}_${tlb}" "saidas diferem"
                fi
            done
        done
    done
done

for frames in 128 256; do
    base="frames${frames}_notlb0_nothread0"
    sem_thread="frames${frames}_notlb0_nothread1"
    sem_tlb="frames${frames}_notlb1_nothread0"
    for pag in fifo lru; do
        for tlb in fifo lru; do
            if cmp -s "$SAIDAS/${base}_${pag}_${tlb}.txt" "$SAIDAS/${sem_thread}_${pag}_${tlb}.txt"; then
                passou "com_thread_igual_a_sem_thread_frames${frames}_${pag}_${tlb}"
            else
                falhou "com_thread_igual_a_sem_thread_frames${frames}_${pag}_${tlb}" "saidas diferem"
            fi
            coluna_pa "$SAIDAS/${base}_${pag}_${tlb}.txt" > "$TMP/a.col"
            coluna_pa "$SAIDAS/${sem_tlb}_${pag}_${tlb}.txt" > "$TMP/b.col"
            if cmp -s "$TMP/a.col" "$TMP/b.col"; then
                passou "enderecos_fisicos_iguais_com_e_sem_tlb_frames${frames}_${pag}_${tlb}"
            else
                falhou "enderecos_fisicos_iguais_com_e_sem_tlb_frames${frames}_${pag}_${tlb}" "colunas diferem"
            fi
        done
        coluna_pa "$SAIDAS/${base}_${pag}_fifo.txt" > "$TMP/a.col"
        coluna_pa "$SAIDAS/${base}_${pag}_lru.txt" > "$TMP/b.col"
        if cmp -s "$TMP/a.col" "$TMP/b.col"; then
            passou "enderecos_fisicos_nao_dependem_do_algoritmo_da_tlb_frames${frames}_${pag}"
        else
            falhou "enderecos_fisicos_nao_dependem_do_algoritmo_da_tlb_frames${frames}_${pag}" "colunas diferem"
        fi
        if cmp -s "$SAIDAS/${sem_tlb}_${pag}_fifo.txt" "$SAIDAS/${sem_tlb}_${pag}_lru.txt"; then
            passou "sem_tlb_ignora_o_argumento_da_tlb_frames${frames}_${pag}"
        else
            falhou "sem_tlb_ignora_o_argumento_da_tlb_frames${frames}_${pag}" "saidas diferem"
        fi
    done
done

for v in frames128_notlb1_nothread1 frames128_notlb0_nothread1; do
    for bin in vm vm_asan; do
        roda "$TMP/$v/$bin" "$SAIDAS/grande_${v}_${bin}.txt" lru fifo "$TMP/grande.txt"
        linhas=$(wc -l < "$SAIDAS/grande_${v}_${bin}.txt")
        maior=$(awk '/^Virtual address:/ { f = int($(NF - 2) / 256); if (f > m) m = f } END { print m + 0 }' "$SAIDAS/grande_${v}_${bin}.txt")
        if [ "$COD" -eq 0 ] && [ "$linhas" -eq 100000 ] && [ "$maior" -lt 128 ]; then
            passou "100000_enderecos_${v}_${bin}"
        else
            falhou "100000_enderecos_${v}_${bin}" "codigo $COD, $linhas linhas (esperado 100000), maior frame $maior"
        fi
    done
done

dir="$TMP/validacao"
copia_fontes "$dir"
for ruim in FRAMES=64 FRAMES= FRAMES=abc NOTLB=0 NOTLB=2 NOTHREAD=0 NOTHREAD=x; do
    make -C "$dir" "$ruim" vm > "$dir/make.log" 2>&1
    cod=$?
    if [ "$cod" -ne 0 ] && grep -q ' deve ser ' "$dir/make.log" && [ ! -e "$dir/vm" ]; then
        passou "make_rejeita_${ruim:-vazio}"
    else
        falhou "make_rejeita_${ruim:-vazio}" "codigo $cod: $(tail -n 2 "$dir/make.log" | tr '\n' ' ')"
    fi
done

dir="$TMP/recompila"
copia_fontes "$dir"
maior_frame() {
    roda "$dir/vm" "$TMP/recompila.txt" lru fifo
    awk '/^Virtual address:/ { f = int($(NF - 2) / 256); if (f > m) m = f } END { print m + 0 }' "$TMP/recompila.txt"
}
make -C "$dir" vm > "$dir/make.log" 2>&1
a=$(maior_frame)
make -C "$dir" FRAMES=256 vm > "$dir/make.log" 2>&1
b=$(maior_frame)
make -C "$dir" vm > "$dir/make.log" 2>&1
c=$(maior_frame)
if [ "$a" = 127 ] && [ "$b" = "$((DISTINTAS - 1))" ] && [ "$c" = 127 ]; then
    passou "make_recompila_ao_trocar_FRAMES"
else
    falhou "make_recompila_ao_trocar_FRAMES" "maior frame $a, $b, $c; esperado 127, $((DISTINTAS - 1)), 127"
fi
make -C "$dir" NOTLB=1 vm > "$dir/make.log" 2>&1
roda "$dir/vm" "$TMP/recompila.txt" lru fifo
if grep -q ' TLB: ' "$TMP/recompila.txt"; then
    falhou "make_recompila_ao_ligar_NOTLB" "a saida ainda tem a coluna TLB"
else
    passou "make_recompila_ao_ligar_NOTLB"
fi
make -C "$dir" vm > "$dir/make.log" 2>&1
roda "$dir/vm" "$TMP/recompila.txt" lru fifo
if grep -q ' TLB: ' "$TMP/recompila.txt"; then
    passou "make_recompila_ao_desligar_NOTLB"
else
    falhou "make_recompila_ao_desligar_NOTLB" "a saida nao tem a coluna TLB"
fi

echo "Casos OK: $OK, FALHOU: $FALHOU"
[ "$FALHOU" -eq 0 ]
