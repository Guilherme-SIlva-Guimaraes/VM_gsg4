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
python3 -I "$RAIZ/tests/modelo.py" "$DADOS/addresses.txt" "$DADOS/BACKING_STORE.bin" lru fifo 128 tlb arquivo > "$TMP/esperado_arquivo.txt"

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
    elif [ "$(lista_w)" != "BACKING_STORE.bin addresses.txt correct.txt " ]; then
        falhou "$nome" "arquivos no diretorio: $(lista_w)"
    elif ! cmp -s "$W/correct.txt" "$TMP/esperado_arquivo.txt"; then
        falhou "$nome" "correct.txt difere do modelo: $(cmp "$W/correct.txt" "$TMP/esperado_arquivo.txt" 2>&1 | head -n 1)"
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

if [ -f "$W/correct.txt" ] && [ "$(wc -l < "$W/correct.txt")" -eq 1005 ] && head -n 1000 "$W/correct.txt" | cmp -s - "$TMP/saida"; then
    passou correct_txt_tem_as_linhas_da_saida_mais_5_de_estatistica
else
    falhou correct_txt_tem_as_linhas_da_saida_mais_5_de_estatistica "correct.txt ausente ou com linhas erradas"
fi

novo_w
printf 'velho\n' > "$W/correct.txt"
rodar addresses.txt lru fifo
confere_sucesso substitui_correct_txt_antigo

for ruim in "addresses.txt xyz fifo" "addresses.txt lru abc" "naoexiste.txt lru fifo" "addresses.txt lru"; do
    novo_w
    printf 'velho\n' > "$W/correct.txt"
    rodar $ruim
    if [ "$COD" -ne 1 ] || [ -s "$TMP/saida" ] || [ "$(cat "$W/correct.txt")" != "velho" ]; then
        falhou "erro_nao_altera_correct_txt_$(echo "$ruim" | tr ' ' '_')" "codigo $COD, stdout $(wc -c < "$TMP/saida") bytes"
    else
        passou "erro_nao_altera_correct_txt_$(echo "$ruim" | tr ' ' '_')"
    fi
done

if [ "$(id -u)" -eq 0 ]; then
    pulado diretorio_somente_leitura_avisa_e_imprime "rodando como root, chmod nao impede a gravacao"
else
    novo_w
    chmod 555 "$W"
    rodar addresses.txt lru fifo
    chmod 755 "$W"
    if [ "$COD" -ne 0 ]; then
        falhou diretorio_somente_leitura_avisa_e_imprime "codigo $COD, esperado 0: $(resumo_erro)"
    elif ! cmp -s "$TMP/saida" "$TMP/esperado.txt"; then
        falhou diretorio_somente_leitura_avisa_e_imprime "saida padrao difere do modelo"
    elif [ -e "$W/correct.txt" ]; then
        falhou diretorio_somente_leitura_avisa_e_imprime "correct.txt apareceu"
    elif ! head -n 1 "$TMP/erro" | grep -q '^aviso: '; then
        falhou diretorio_somente_leitura_avisa_e_imprime "sem aviso no stderr: $(resumo_erro)"
    else
        passou diretorio_somente_leitura_avisa_e_imprime
    fi
fi

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
    elif [ -e "$W/correct.txt" ]; then
        falhou saida_cheia_da_erro "correct.txt foi criado apesar da falha"
    else
        passou saida_cheia_da_erro
    fi
else
    pulado saida_cheia_da_erro "sem /dev/full neste sistema"
fi

echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
[ "$FALHOU" -eq 0 ]
