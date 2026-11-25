RAIZ=$(cd "$(dirname "$0")/.." && pwd)
DADOS="$RAIZ/tests/dados"
CASOS="$RAIZ/tests/casos"
ESPERADO="$RAIZ/tests/esperado/correct.txt"
TMP=$(mktemp -d /tmp/vmmodelo.XXXXXX)
FONTES="Makefile config.h entrada.c entrada.h memoria.c memoria.h simulador.c simulador.h tlb.c tlb.h vm.c"
PEQUENAS="um_zero um_maximo repetido sequencial_129 aleatorio_50 todas_256_ida_e_volta"
OK=0
FALHOU=0
trap 'rm -rf "$TMP"' EXIT

passou() { OK=$((OK + 1)); echo "OK      $1"; }
falhou() { FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 ($2)"; }

copia_fontes() {
    rm -rf "$1"
    mkdir -p "$1"
    for f in $FONTES; do
        cp "$RAIZ/$f" "$1/$f"
    done
}

constroi() {
    local nome=$1
    shift
    local dir="$TMP/bin/$nome"
    local cod
    copia_fontes "$dir"
    make -C "$dir" "$@" vm vm_asan > "$dir/make.log" 2>&1
    cod=$?
    if [ "$cod" -ne 0 ]; then
        falhou "compila_$nome" "make saiu com $cod: $(tail -n 3 "$dir/make.log" | tr '\n' ' ')"
        return 1
    fi
    if grep -q -i warning "$dir/make.log"; then
        falhou "compila_$nome" "make mostrou warning: $(grep -i -m 1 warning "$dir/make.log")"
        return 1
    fi
    passou "compila_$nome"
}

roda_c() {
    local bin=$1
    local entrada=$2
    local pag=$3
    local tlb=$4
    local destino=$5
    local w="$TMP/w"
    rm -rf "$w"
    mkdir -p "$w"
    cp "$DADOS/BACKING_STORE.bin" "$w/"
    cp "$entrada" "$w/addresses.txt"
    ( cd "$w" && "$bin" addresses.txt "$pag" "$tlb" ) > "$destino" 2> "$TMP/erro"
    COD=$?
    ARQUIVOS=$(ls -A "$w" | sort | tr '\n' ' ')
}

modelo() {
    python3 -I "$RAIZ/tests/modelo.py" "$1" "$DADOS/BACKING_STORE.bin" "$2" "$3" "$4" "$5" > "$6"
}

compara() {
    local nome=$1
    local entrada=$2
    local pag=$3
    local tlb=$4
    local esperado=$5
    local ruins=""
    local primeira=""
    local b
    shift 5
    for b in "$@"; do
        roda_c "$TMP/bin/$b" "$entrada" "$pag" "$tlb" "$TMP/c.txt"
        if [ "$COD" -ne 0 ] || [ -s "$TMP/erro" ] || [ "$ARQUIVOS" != "BACKING_STORE.bin addresses.txt " ] || ! cmp -s "$TMP/c.txt" "$esperado"; then
            ruins="$ruins $b(codigo $COD)"
            if [ -z "$primeira" ]; then
                primeira=$(cmp "$TMP/c.txt" "$esperado" 2>&1 | head -n 1)
            fi
        fi
    done
    if [ -z "$ruins" ]; then
        passou "$nome"
    else
        falhou "$nome" "diferem:$ruins; $primeira"
    fi
}

mkdir -p "$TMP/bin" "$TMP/in"
constroi sem_thread_128 FRAMES=128 NOTHREAD=1
constroi sem_thread_256 FRAMES=256 NOTHREAD=1
constroi com_thread_128 FRAMES=128
constroi com_thread_256 FRAMES=256
constroi sem_tlb_128 FRAMES=128 NOTLB=1
constroi sem_tlb_256 FRAMES=256 NOTLB=1

python3 -I "$RAIZ/tests/gera_entradas.py" "$TMP/in"

head -n 1000 "$ESPERADO" > "$TMP/professor1000.txt"
modelo "$DADOS/addresses.txt" lru fifo 128 tlb "$TMP/m.txt"
if cmp -s "$TMP/m.txt" "$TMP/professor1000.txt"; then
    passou modelo_python_igual_as_1000_linhas_do_professor
else
    falhou modelo_python_igual_as_1000_linhas_do_professor "$(cmp "$TMP/m.txt" "$TMP/professor1000.txt" 2>&1 | head -n 1)"
fi

for c in "tlb fifo tlb.fifo" "tlb lru tlb.lru" "pagina fifo pagina.fifo" "pagina lru pagina.lru" "invalida fifo invalida.fifo" "invalida lru invalida.lru"; do
    set -- $c
    caso=$1
    alg=$2
    esperado="$CASOS/$3.esperado"
    case "$caso" in
        tlb) pag=fifo; tlb_alg=$alg ;;
        pagina) pag=$alg; tlb_alg=fifo ;;
        invalida) pag=fifo; tlb_alg=$alg ;;
    esac
    modelo "$CASOS/$caso.txt" "$pag" "$tlb_alg" 128 tlb "$TMP/m.txt"
    if cmp -s "$TMP/m.txt" "$esperado"; then
        passou "modelo_python_igual_ao_calculo_a_mao_$3"
    else
        falhou "modelo_python_igual_ao_calculo_a_mao_$3" "$(cmp "$TMP/m.txt" "$esperado" 2>&1 | head -n 1)"
    fi
done

BINS="sem_thread_128/vm sem_thread_128/vm_asan com_thread_128/vm com_thread_128/vm_asan"
compara a_mao_tlb_fifo_pagina_fifo "$CASOS/tlb.txt" fifo fifo "$CASOS/tlb.fifo.esperado" $BINS
compara a_mao_tlb_fifo_pagina_lru "$CASOS/tlb.txt" lru fifo "$CASOS/tlb.fifo.esperado" $BINS
compara a_mao_tlb_lru_pagina_fifo "$CASOS/tlb.txt" fifo lru "$CASOS/tlb.lru.esperado" $BINS
compara a_mao_tlb_lru_pagina_lru "$CASOS/tlb.txt" lru lru "$CASOS/tlb.lru.esperado" $BINS
compara a_mao_pagina_fifo_despeja_a_mais_antiga_e_invalida_a_tlb "$CASOS/pagina.txt" fifo fifo "$CASOS/pagina.fifo.esperado" $BINS
compara a_mao_pagina_lru_despeja_a_menos_usada "$CASOS/pagina.txt" lru fifo "$CASOS/pagina.lru.esperado" $BINS
compara a_mao_posicao_livre_da_tlb_fifo_depois_de_invalidar "$CASOS/invalida.txt" fifo fifo "$CASOS/invalida.fifo.esperado" $BINS
compara a_mao_posicao_livre_da_tlb_lru_depois_de_invalidar "$CASOS/invalida.txt" fifo lru "$CASOS/invalida.lru.esperado" $BINS

for frames in 128 256; do
    for entrada in "$TMP"/in/*.txt; do
        base=$(basename "$entrada" .txt)
        pequena=0
        case " $PEQUENAS " in
            *" $base "*) pequena=1 ;;
        esac
        for pag in fifo lru; do
            for tlb in fifo lru; do
                modelo "$entrada" $pag $tlb $frames tlb "$TMP/m.txt"
                bins="sem_thread_$frames/vm sem_thread_$frames/vm_asan"
                if [ "$pequena" -eq 1 ]; then
                    bins="$bins com_thread_$frames/vm com_thread_$frames/vm_asan"
                fi
                compara "modelo_frames${frames}_com_tlb_${base}_pagina_${pag}_tlb_${tlb}" "$entrada" $pag $tlb "$TMP/m.txt" $bins
            done
            modelo "$entrada" $pag fifo $frames semtlb "$TMP/m.txt"
            compara "modelo_frames${frames}_sem_tlb_${base}_pagina_${pag}" "$entrada" $pag fifo "$TMP/m.txt" sem_tlb_$frames/vm sem_tlb_$frames/vm_asan
        done
    done
done

echo "Casos OK: $OK, FALHOU: $FALHOU"
[ "$FALHOU" -eq 0 ]
