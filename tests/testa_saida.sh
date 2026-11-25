if [ -z "$1" ] || [ ! -x "$1" ]; then
    echo "uso: bash tests/testa_saida.sh ./vm"
    exit 2
fi

VM=$(readlink -f "$1")
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/vmsaida.XXXXXX)
DADOS="$TMP/dados"
W="$TMP/w"
OK=0
FALHOU=0
PULADO=0
trap 'rm -rf "$TMP"' EXIT

passou() { OK=$((OK + 1)); echo "OK      $1"; }
falhou() { FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 ($2)"; }
pulado() { PULADO=$((PULADO + 1)); echo "PULADO  $1 ($2)"; }

python3 -I "$RAIZ/tests/gera_dados.py" "$DADOS"
python3 -I "$RAIZ/tests/modelo.py" "$DADOS/addresses.txt" "$DADOS/BACKING_STORE.bin" lru fifo 128 tlb > "$TMP/esperado.txt"

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
    elif ! cmp -s "$TMP/saida" "$TMP/esperado.txt"; then
        falhou "$nome" "saida difere do modelo: $(cmp "$TMP/saida" "$TMP/esperado.txt" 2>&1 | head -n 1)"
    elif [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt " ]; then
        falhou "$nome" "arquivos no diretorio: $(lista_w)"
    else
        passou "$nome"
    fi
}

echo "binario: $1"

novo_w
rodar addresses.txt lru fifo
confere_sucesso lru_fifo_na_saida_padrao_igual_ao_modelo

rodar addresses.txt lru fifo
confere_sucesso segunda_execucao_no_mesmo_diretorio

if [ "$(tail -c 1 "$TMP/saida" | od -An -c | tr -d ' ')" = '\n' ]; then
    passou saida_termina_com_quebra_de_linha
else
    falhou saida_termina_com_quebra_de_linha "ultimo byte nao e LF"
fi

if [ "$(wc -l < "$TMP/saida")" -eq 1000 ] && ! grep -q -E 'Number of|Page Fault|TLB Hit' "$TMP/saida"; then
    passou saida_so_com_linhas_de_endereco_sem_estatisticas
else
    falhou saida_so_com_linhas_de_endereco_sem_estatisticas "linhas: $(wc -l < "$TMP/saida")"
fi

novo_w
printf 'velho\n' > "$W/correct.txt"
rodar addresses.txt lru fifo
if [ "$COD" -ne 0 ] || [ "$(cat "$W/correct.txt")" != "velho" ] || [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt correct.txt " ]; then
    falhou nao_cria_nem_altera_correct_txt "codigo $COD, arquivos: $(lista_w)"
else
    passou nao_cria_nem_altera_correct_txt
fi

novo_w
chmod 555 "$W"
rodar addresses.txt lru fifo
chmod 755 "$W"
confere_sucesso funciona_em_diretorio_somente_leitura

novo_w
( cd "$W" && "$VM" addresses.txt lru fifo | cat > "$TMP/saida_cat"; exit "${PIPESTATUS[0]}" ) 2> "$TMP/erro"
COD=$?
if [ "$COD" -eq 0 ] && cmp -s "$TMP/saida_cat" "$TMP/esperado.txt"; then
    passou saida_igual_atraves_de_pipe
else
    falhou saida_igual_atraves_de_pipe "codigo $COD"
fi

if [ -w /dev/full ]; then
    novo_w
    ( cd "$W" && "$VM" addresses.txt lru fifo ) > /dev/full 2> "$TMP/erro"
    COD=$?
    if [ "$COD" -ne 1 ]; then
        falhou saida_cheia_da_erro "codigo $COD, esperado 1: $(resumo_erro)"
    elif ! head -n 1 "$TMP/erro" | grep -q '^erro: falha ao escrever a saida'; then
        falhou saida_cheia_da_erro "mensagem inesperada: $(resumo_erro)"
    else
        passou saida_cheia_da_erro
    fi
else
    pulado saida_cheia_da_erro "sem /dev/full neste sistema"
fi

echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
[ "$FALHOU" -eq 0 ]
