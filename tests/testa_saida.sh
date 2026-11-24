if [ -z "$1" ] || [ ! -x "$1" ]; then
    echo "uso: bash tests/testa_saida.sh ./vm"
    exit 2
fi

VM=$(readlink -f "$1")
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
DADOS="$RAIZ/tests/dados"
ESPERADO="$RAIZ/tests/esperado/correct.txt"
TMP=$(mktemp -d /tmp/vmsaida.XXXXXX)
W="$TMP/w"
OK=0
FALHOU=0
PULADO=0
trap 'rm -rf "$TMP"' EXIT

passou() { OK=$((OK + 1)); echo "OK      $1"; }
falhou() { FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 ($2)"; }
pulado() { PULADO=$((PULADO + 1)); echo "PULADO  $1 ($2)"; }

novo_w() {
    rm -rf "$W"
    mkdir -p "$W"
    cp "$DADOS/BACKING_STORE.bin" "$DADOS/addresses.txt" "$W/"
}

rodar() {
    ( cd "$W" && "$VM" "$@" ) > "$TMP/saida" 2> "$TMP/erro"
    COD=$?
}

lista_w() { ls -A "$W" | sort | tr '\n' ' '; }
resumo_erro() { head -c 160 "$TMP/erro" | tr '\n' ' '; }

confere_sucesso() {
    nome=$1
    if [ "$COD" -ne 0 ]; then
        falhou "$nome" "codigo $COD, esperado 0: $(resumo_erro)"
    elif [ -s "$TMP/erro" ]; then
        falhou "$nome" "stderr nao vazio: $(resumo_erro)"
    elif [ -s "$TMP/saida" ]; then
        falhou "$nome" "stdout nao vazio"
    elif ! cmp -s "$W/correct.txt" "$ESPERADO"; then
        falhou "$nome" "correct.txt difere do professor: $(cmp "$W/correct.txt" "$ESPERADO" 2>&1 | head -n 1)"
    elif [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt correct.txt " ]; then
        falhou "$nome" "arquivos no diretorio: $(lista_w)"
    else
        passou "$nome"
    fi
}

echo "binario: $1"

novo_w
rodar addresses.txt lru fifo
confere_sucesso professor_lru_fifo_cmp_byte_a_byte

rodar addresses.txt lru fifo
confere_sucesso professor_segunda_execucao_no_mesmo_diretorio

novo_w
printf 'velho\n' > "$W/correct.txt"
rodar addresses.txt lru fifo
confere_sucesso professor_sobrescreve_correct_antigo

novo_w
rodar addresses.txt lru fifo
modo_esperado=$(printf '%o' $((0666 & ~$(umask))))
modo_real=$(stat -c %a "$W/correct.txt")
if [ "$modo_real" = "$modo_esperado" ]; then
    passou permissoes_do_correct_seguem_o_umask
else
    falhou permissoes_do_correct_seguem_o_umask "modo $modo_real, esperado $modo_esperado"
fi

novo_w
mkdir "$W/correct.txt"
rodar addresses.txt lru fifo
if [ "$COD" -ne 1 ]; then
    falhou saida_e_diretorio "codigo $COD, esperado 1: $(resumo_erro)"
elif ! head -n 1 "$TMP/erro" | grep -q '^erro: nao foi possivel gravar correct.txt'; then
    falhou saida_e_diretorio "mensagem inesperada: $(resumo_erro)"
elif [ ! -d "$W/correct.txt" ]; then
    falhou saida_e_diretorio "o diretorio correct.txt sumiu"
elif [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt correct.txt " ]; then
    falhou saida_e_diretorio "sobrou arquivo temporario: $(lista_w)"
elif [ -s "$TMP/saida" ]; then
    falhou saida_e_diretorio "stdout nao vazio"
else
    passou saida_e_diretorio
fi

if [ "$(id -u)" -eq 0 ]; then
    pulado diretorio_sem_permissao_de_escrita "executando como root"
else
    novo_w
    chmod 555 "$W"
    rodar addresses.txt lru fifo
    chmod 755 "$W"
    if [ "$COD" -ne 1 ]; then
        falhou diretorio_sem_permissao_de_escrita "codigo $COD, esperado 1: $(resumo_erro)"
    elif ! head -n 1 "$TMP/erro" | grep -q '^erro: nao foi possivel criar o arquivo temporario'; then
        falhou diretorio_sem_permissao_de_escrita "mensagem inesperada: $(resumo_erro)"
    elif [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt " ]; then
        falhou diretorio_sem_permissao_de_escrita "arquivos no diretorio: $(lista_w)"
    else
        passou diretorio_sem_permissao_de_escrita
    fi
fi

awk 'BEGIN { for (i = 0; i < 100000; i++) print i % 65536 }' > "$TMP/grande.txt"

caso_sinal() {
    nome=$1
    sinal=$2
    esperado=$3
    novo_w
    cp "$TMP/grande.txt" "$W/grande.txt"
    ( cd "$W" && exec "$VM" grande.txt lru fifo ) > "$TMP/saida" 2> "$TMP/erro" &
    pid=$!
    sleep 1
    if ! ls "$W" | grep -q '^correct.txt.tmp'; then
        kill -s KILL "$pid" 2> /dev/null
        wait "$pid" 2> /dev/null
        falhou "$nome" "o arquivo temporario nao existia antes do sinal"
        return
    fi
    kill -s "$sinal" "$pid"
    wait "$pid"
    cod=$?
    if [ "$cod" -ne "$esperado" ]; then
        falhou "$nome" "codigo $cod, esperado $esperado"
    elif [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt grande.txt " ]; then
        falhou "$nome" "arquivos no diretorio: $(lista_w)"
    elif [ -s "$TMP/erro" ]; then
        falhou "$nome" "stderr nao vazio: $(resumo_erro)"
    else
        passou "$nome"
    fi
}

caso_sinal sinal_term_remove_temporario_e_nao_cria_correct TERM 143
caso_sinal sinal_int_remove_temporario_e_nao_cria_correct INT 130
caso_sinal sinal_hup_remove_temporario_e_nao_cria_correct HUP 129

echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
[ "$FALHOU" -eq 0 ]
