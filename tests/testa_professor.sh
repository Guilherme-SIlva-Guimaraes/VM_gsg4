if [ -z "$1" ] || [ ! -x "$1" ]; then
    echo "uso: PROFESSOR=pasta bash tests/testa_professor.sh ./vm"
    exit 2
fi

VM=$(readlink -f "$1")
TMP=$(mktemp -d /tmp/vmprof.XXXXXX)
W="$TMP/w"
OK=0
FALHOU=0
PULADO=0
trap 'rm -rf "$TMP"' EXIT

passou() { OK=$((OK + 1)); echo "OK      $1"; }
falhou() { FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 ($2)"; }
pulado() { PULADO=$((PULADO + 1)); echo "PULADO  $1 ($2)"; }

echo "binario: $1"

if [ -z "$PROFESSOR" ]; then
    pulado professor_lru_fifo_cmp_byte_a_byte "defina PROFESSOR=pasta com os arquivos do professor"
    echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
    exit 0
fi

ENDERECOS="$PROFESSOR/addresses.txt"
[ -f "$ENDERECOS" ] || ENDERECOS="$PROFESSOR/address.txt"
if [ ! -f "$ENDERECOS" ] || [ ! -f "$PROFESSOR/BACKING_STORE.bin" ] || [ ! -f "$PROFESSOR/correct.txt" ]; then
    falhou professor_arquivos_na_pasta "faltam addresses.txt, BACKING_STORE.bin ou correct.txt em $PROFESSOR"
    echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
    exit 1
fi

mkdir -p "$W"
cp "$ENDERECOS" "$W/addresses.txt"
cp "$PROFESSOR/BACKING_STORE.bin" "$W/"
head -n 1000 "$PROFESSOR/correct.txt" > "$TMP/esperado1000.txt"
( cd "$W" && "$VM" addresses.txt lru fifo ) > "$TMP/saida" 2> "$TMP/erro"
COD=$?
if [ "$COD" -ne 0 ]; then
    falhou professor_lru_fifo_cmp_byte_a_byte "codigo $COD: $(head -c 160 "$TMP/erro" | tr '\n' ' ')"
elif [ -s "$TMP/erro" ]; then
    falhou professor_lru_fifo_cmp_byte_a_byte "stderr nao vazio"
elif ! cmp -s "$TMP/saida" "$TMP/esperado1000.txt"; then
    falhou professor_lru_fifo_cmp_byte_a_byte "saida difere das 1000 linhas do correct.txt: $(cmp "$TMP/saida" "$TMP/esperado1000.txt" 2>&1 | head -n 1)"
elif [ "$(ls -A "$W" | sort | tr '\n' ' ')" != "BACKING_STORE.bin addresses.txt correct.txt " ]; then
    falhou professor_lru_fifo_cmp_byte_a_byte "arquivos no diretorio: $(ls -A "$W" | tr '\n' ' ')"
elif ! cmp -s "$W/correct.txt" "$PROFESSOR/correct.txt"; then
    falhou professor_lru_fifo_cmp_byte_a_byte "correct.txt gravado difere do correct.txt do professor: $(cmp "$W/correct.txt" "$PROFESSOR/correct.txt" 2>&1 | head -n 1)"
else
    passou professor_lru_fifo_cmp_byte_a_byte
fi

echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
[ "$FALHOU" -eq 0 ]
