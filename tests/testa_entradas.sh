if [ -z "$1" ] || [ ! -x "$1" ]; then
    echo "uso: bash tests/testa_entradas.sh ./vm"
    exit 2
fi

VM=$(readlink -f "$1")
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
DADOS="$RAIZ/tests/dados"
TMP=$(mktemp -d /tmp/vmentradas.XXXXXX)
IN="$TMP/in"
W="$TMP/w"
OK=0
FALHOU=0
PULADO=0
mkdir -p "$IN"
trap 'rm -rf "$TMP"' EXIT

passou() { OK=$((OK + 1)); echo "OK      $1"; }
falhou() { FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 ($2)"; }
pulado() { PULADO=$((PULADO + 1)); echo "PULADO  $1 ($2)"; }

mk() { printf -- "$2" > "$IN/$1"; }
repete() { head -c "$2" /dev/zero | tr '\0' "$1"; }
arq() { printf '%s/%s' "$IN" "$1"; }
resumo_erro() { head -c 160 "$TMP/erro" | tr '\n' ' '; }

novo_w() {
    rm -rf "$W"
    mkdir -p "$W"
    cp "$DADOS/BACKING_STORE.bin" "$W/BACKING_STORE.bin"
    "${PREP:-true}"
}

rodar() {
    ( cd "$W" && "$VM" "$@" ) > "$TMP/saida" 2> "$TMP/erro"
    COD=$?
}

so_ascii() { ! LC_ALL=C grep -q -v '^[ -~]*$' "$1"; }
sem_sanitizer() { ! grep -q -i -e sanitizer -e 'runtime error' "$1"; }
conta_enderecos() { tr -d '\r' < "$1" | awk 'NF { n++ } END { print n + 0 }'; }
formato_ok() { ! grep -q -v -E '^Virtual address: [0-9]+ TLB: [0-9]+ Physical address: [0-9]+ Value: -?[0-9]+$' "$1"; }

caso_ok() {
    nome=$1
    shift
    novo_w
    ls -A "$W" > "$TMP/antes"
    rodar "$@"
    if [ "$COD" -ne 0 ]; then
        falhou "$nome" "codigo $COD, esperado 0: $(resumo_erro)"
        return
    fi
    if [ -s "$TMP/erro" ]; then
        falhou "$nome" "stderr nao vazio: $(resumo_erro)"
        return
    fi
    esperadas=$(conta_enderecos "$1")
    linhas=$(wc -l < "$TMP/saida")
    if [ "$linhas" -ne "$esperadas" ]; then
        falhou "$nome" "$linhas linhas na saida, esperado $esperadas"
        return
    fi
    if ! formato_ok "$TMP/saida"; then
        falhou "$nome" "linha fora do formato Virtual address: ... Value: ..."
        return
    fi
    ls -A "$W" > "$TMP/depois"
    if ! cmp -s "$TMP/antes" "$TMP/depois"; then
        falhou "$nome" "arquivos criados ou removidos no diretorio de trabalho"
        return
    fi
    passou "$nome"
}

caso_erro() {
    nome=$1
    trecho=$2
    shift 2
    novo_w
    ls -A "$W" > "$TMP/antes"
    rodar "$@"
    if [ "$COD" -ne 1 ]; then
        falhou "$nome" "codigo $COD, esperado 1: $(resumo_erro)"
        return
    fi
    if ! head -n 1 "$TMP/erro" | grep -q '^erro: '; then
        falhou "$nome" "primeira linha do stderr nao comeca com 'erro: ': $(resumo_erro)"
        return
    fi
    if ! grep -q -F -e "$trecho" "$TMP/erro"; then
        falhou "$nome" "stderr sem o trecho '$trecho': $(resumo_erro)"
        return
    fi
    if [ -s "$TMP/saida" ]; then
        falhou "$nome" "stdout nao vazio"
        return
    fi
    if ! so_ascii "$TMP/erro"; then
        falhou "$nome" "stderr com byte fora de ASCII imprimivel"
        return
    fi
    if ! sem_sanitizer "$TMP/erro"; then
        falhou "$nome" "sanitizer reportou problema: $(resumo_erro)"
        return
    fi
    ls -A "$W" > "$TMP/depois"
    if ! cmp -s "$TMP/antes" "$TMP/depois"; then
        falhou "$nome" "arquivos criados ou removidos no diretorio de trabalho"
        return
    fi
    passou "$nome"
}

prep_sem_backing() { rm -f "$W/BACKING_STORE.bin"; }
prep_backing_diretorio() { rm -f "$W/BACKING_STORE.bin"; mkdir "$W/BACKING_STORE.bin"; }
prep_backing_vazio() { : > "$W/BACKING_STORE.bin"; }
prep_backing_menor() { head -c 65535 "$DADOS/BACKING_STORE.bin" > "$W/BACKING_STORE.bin"; }
prep_backing_maior() { { cat "$DADOS/BACKING_STORE.bin"; printf 'x'; } > "$W/BACKING_STORE.bin"; }
prep_backing_link_quebrado() { rm -f "$W/BACKING_STORE.bin"; ln -s "$W/nao_existe" "$W/BACKING_STORE.bin"; }
prep_backing_link_valido() { mv "$W/BACKING_STORE.bin" "$W/real.bin"; ln -s "$W/real.bin" "$W/BACKING_STORE.bin"; }
prep_backing_sem_permissao() { chmod 000 "$W/BACKING_STORE.bin"; }

echo "binario: $1"

mk ok '5\n10\n'
mk vazio ''
mk so_lf '\n'
mk so_crlf '\r\n'
mk branca_meio '5\n\n10\n'
mk branca_fim '5\n10\n\n'
mk so_espacos '5\n   \n'
mk espaco_inicio ' 5\n'
mk tab_inicio '\t5\n'
mk tab_fim '5\t\n'
mk espaco_meio '1 2\n'
mk nulo_meio '12\0\n'
mk nulo_inicio '\0'
mk nulo_ultima '5\n10\0'
mk letras '12a\n'
mk so_letras 'abc\n'
mk mais '+5\n'
mk menos '-5\n'
mk menos_zero '-0\n'
mk hex '0x10\n'
mk ponto '1.5\n'
mk virgula '1,5\n'
mk cr_meio '1\r2\n'
mk cr_duplo '5\r\r\n'
mk cr_inicio '\r5\n'
mk acima '65536\n'
mk int_max '2147483647\n'
mk int_max_mais '2147483648\n'
mk int_min '-2147483648\n'
mk uint_max '4294967295\n'
mk vinte_digitos '99999999999999999999\n'
mk quarenta_digitos '9999999999999999999999999999999999999999\n'
mk limite_ok '65535\n0\n'
mk zeros_ok '007\n0\n00065535\n000\n'
mk espacos_fim_ok '5  \n10 \n'
mk sem_lf_ok '5\n10'
mk cr_fim_ok '5\n10\r'
mk crlf_pequeno_ok '5\r\n10 \r\n'
mk um_ok '1\n'
mk sem_permissao '5\n'
chmod 000 "$IN/sem_permissao"
mkdir "$IN/diretorio"
{ repete 1 1048576; printf '\n'; } > "$IN/longa_digitos"
{ repete 0 1048576; printf '5\n'; } > "$IN/longa_zeros_ok"
{ printf '5'; repete ' ' 1048576; printf '\n'; } > "$IN/longa_espacos_ok"
repete a 1048576 > "$IN/longa_letras_sem_lf"
awk 'BEGIN { for (i = 0; i < 3000; i++) print i % 65536 }' > "$IN/muitos_ok"
{ head -n 999 "$DADOS/addresses.txt"; printf 'x\n'; } > "$IN/erro_na_1000"
sed 's/$/\r/' "$DADOS/addresses.txt" > "$IN/oficial_crlf"
head -c -1 "$DADOS/addresses.txt" > "$IN/oficial_sem_lf"

USO='uso: ./vm arquivo_enderecos fifo|lru fifo|lru'

caso_erro args_zero "numero de argumentos invalido (esperado 3, recebido 0)"
caso_erro args_um "recebido 1" "$(arq ok)"
caso_erro args_dois "recebido 2" "$(arq ok)" lru
caso_erro args_quatro "recebido 4" "$(arq ok)" lru fifo extra
caso_erro args_cinco "recebido 5" "$(arq ok)" lru fifo extra mais
caso_erro args_mostra_uso "$USO" "$(arq ok)" lru
caso_erro pagina_maiuscula "algoritmo de pagina invalido 'LRU'" "$(arq ok)" LRU fifo
caso_erro pagina_inicial_maiuscula "algoritmo de pagina invalido 'Fifo'" "$(arq ok)" Fifo fifo
caso_erro pagina_com_espaco "algoritmo de pagina invalido 'lru '" "$(arq ok)" 'lru ' fifo
caso_erro pagina_vazia "algoritmo de pagina invalido ''" "$(arq ok)" '' fifo
caso_erro pagina_invalida "algoritmo de pagina invalido 'xyz'" "$(arq ok)" xyz fifo
caso_erro pagina_nao_ascii "algoritmo de pagina invalido 'l??'" "$(arq ok)" $'l\xc3\xa9' fifo
caso_erro pagina_invalida_mostra_uso "$USO" "$(arq ok)" xyz fifo
caso_erro tlb_maiuscula "algoritmo da TLB invalido 'FIFO'" "$(arq ok)" lru FIFO
caso_erro tlb_com_espaco "algoritmo da TLB invalido ' fifo'" "$(arq ok)" lru ' fifo'
caso_erro tlb_vazia "algoritmo da TLB invalido ''" "$(arq ok)" lru ''
caso_erro tlb_invalida "algoritmo da TLB invalido 'abc'" "$(arq ok)" lru abc
caso_erro pagina_e_tlb_invalidas "algoritmo de pagina invalido 'a'" "$(arq ok)" a b
caso_erro argumentos_antes_do_arquivo "numero de argumentos invalido" "$(arq inexistente)" lru
caso_erro algoritmo_antes_do_arquivo "algoritmo de pagina invalido" "$(arq inexistente)" xyz fifo

caso_ok algoritmos_lru_fifo "$(arq ok)" lru fifo
caso_ok algoritmos_fifo_lru "$(arq ok)" fifo lru
caso_ok algoritmos_fifo_fifo "$(arq ok)" fifo fifo
caso_ok algoritmos_lru_lru "$(arq ok)" lru lru

caso_erro enderecos_ausente "arquivo de enderecos: arquivo nao existe" "$(arq inexistente)" lru fifo
caso_erro enderecos_caminho_vazio "arquivo de enderecos: arquivo nao existe" "" lru fifo
caso_erro enderecos_diretorio "arquivo de enderecos: e um diretorio" "$(arq diretorio)" lru fifo
if [ "$(id -u)" -eq 0 ]; then
    pulado enderecos_sem_permissao "executando como root"
else
    caso_erro enderecos_sem_permissao "arquivo de enderecos: sem permissao de leitura" "$(arq sem_permissao)" lru fifo
fi

caso_ok enderecos_oficial "$DADOS/addresses.txt" lru fifo
caso_ok enderecos_oficial_crlf "$(arq oficial_crlf)" lru fifo
caso_ok enderecos_oficial_sem_lf_final "$(arq oficial_sem_lf)" lru fifo
caso_ok enderecos_limite_65535 "$(arq limite_ok)" lru fifo
caso_ok enderecos_zeros_a_esquerda "$(arq zeros_ok)" lru fifo
caso_ok enderecos_espacos_no_fim "$(arq espacos_fim_ok)" lru fifo
caso_ok enderecos_sem_lf_final "$(arq sem_lf_ok)" lru fifo
caso_ok enderecos_cr_no_fim_do_arquivo "$(arq cr_fim_ok)" lru fifo
caso_ok enderecos_crlf_com_espaco "$(arq crlf_pequeno_ok)" lru fifo
caso_ok enderecos_uma_linha "$(arq um_ok)" lru fifo
caso_ok enderecos_3000_linhas "$(arq muitos_ok)" lru fifo
caso_ok enderecos_linha_longa_zeros "$(arq longa_zeros_ok)" lru fifo
caso_ok enderecos_linha_longa_espacos "$(arq longa_espacos_ok)" lru fifo

caso_erro enderecos_arquivo_vazio "arquivo de enderecos: arquivo vazio" "$(arq vazio)" lru fifo
caso_erro enderecos_so_lf "linha 1: linha em branco" "$(arq so_lf)" lru fifo
caso_erro enderecos_so_crlf "linha 1: linha em branco ou caractere \\r no inicio da linha" "$(arq so_crlf)" lru fifo
caso_erro enderecos_branca_no_meio "linha 2: linha em branco" "$(arq branca_meio)" lru fifo
caso_erro enderecos_branca_no_fim "linha 3: linha em branco" "$(arq branca_fim)" lru fifo
caso_erro enderecos_so_espacos "linha 2: espaco no inicio da linha" "$(arq so_espacos)" lru fifo
caso_erro enderecos_espaco_no_inicio "linha 1: espaco no inicio da linha" "$(arq espaco_inicio)" lru fifo
caso_erro enderecos_tab_no_inicio "linha 1: caractere invalido (0x09)" "$(arq tab_inicio)" lru fifo
caso_erro enderecos_tab_no_fim "linha 1: caractere invalido (0x09)" "$(arq tab_fim)" lru fifo
caso_erro enderecos_espaco_no_meio "linha 1: espaco no meio da linha" "$(arq espaco_meio)" lru fifo
caso_erro enderecos_nulo_no_meio "linha 1: byte nulo" "$(arq nulo_meio)" lru fifo
caso_erro enderecos_nulo_no_inicio "linha 1: byte nulo" "$(arq nulo_inicio)" lru fifo
caso_erro enderecos_nulo_na_ultima_linha "linha 2: byte nulo" "$(arq nulo_ultima)" lru fifo
caso_erro enderecos_letra_no_fim "linha 1: caractere invalido (0x61)" "$(arq letras)" lru fifo
caso_erro enderecos_so_letras "linha 1: caractere invalido (0x61)" "$(arq so_letras)" lru fifo
caso_erro enderecos_sinal_mais "linha 1: caractere invalido (0x2B)" "$(arq mais)" lru fifo
caso_erro enderecos_sinal_menos "linha 1: caractere invalido (0x2D)" "$(arq menos)" lru fifo
caso_erro enderecos_menos_zero "linha 1: caractere invalido (0x2D)" "$(arq menos_zero)" lru fifo
caso_erro enderecos_hexadecimal "linha 1: caractere invalido (0x78)" "$(arq hex)" lru fifo
caso_erro enderecos_ponto_decimal "linha 1: caractere invalido (0x2E)" "$(arq ponto)" lru fifo
caso_erro enderecos_virgula "linha 1: caractere invalido (0x2C)" "$(arq virgula)" lru fifo
caso_erro enderecos_cr_no_meio "linha 1: caractere \\r fora do fim da linha" "$(arq cr_meio)" lru fifo
caso_erro enderecos_cr_duplo "linha 1: caractere \\r fora do fim da linha" "$(arq cr_duplo)" lru fifo
caso_erro enderecos_cr_no_inicio "linha 1: linha em branco ou caractere \\r no inicio da linha" "$(arq cr_inicio)" lru fifo
caso_erro enderecos_65536 "linha 1: endereco acima de 65535" "$(arq acima)" lru fifo
caso_erro enderecos_int_max "linha 1: endereco acima de 65535" "$(arq int_max)" lru fifo
caso_erro enderecos_int_max_mais_um "linha 1: endereco acima de 65535" "$(arq int_max_mais)" lru fifo
caso_erro enderecos_int_min "linha 1: caractere invalido (0x2D)" "$(arq int_min)" lru fifo
caso_erro enderecos_uint_max "linha 1: endereco acima de 65535" "$(arq uint_max)" lru fifo
caso_erro enderecos_vinte_digitos "linha 1: endereco acima de 65535" "$(arq vinte_digitos)" lru fifo
caso_erro enderecos_quarenta_digitos "linha 1: endereco acima de 65535" "$(arq quarenta_digitos)" lru fifo
caso_erro enderecos_linha_longa_digitos "linha 1: endereco acima de 65535" "$(arq longa_digitos)" lru fifo
caso_erro enderecos_linha_longa_letras "linha 1: caractere invalido (0x61)" "$(arq longa_letras_sem_lf)" lru fifo
caso_erro enderecos_erro_na_linha_1000 "linha 1000: caractere invalido (0x78)" "$(arq erro_na_1000)" lru fifo

PREP=prep_sem_backing caso_erro backing_ausente "BACKING_STORE.bin: arquivo nao existe" "$(arq ok)" lru fifo
PREP=prep_backing_diretorio caso_erro backing_diretorio "BACKING_STORE.bin: e um diretorio" "$(arq ok)" lru fifo
PREP=prep_backing_vazio caso_erro backing_vazio "BACKING_STORE.bin: tamanho invalido (esperado 65536 bytes)" "$(arq ok)" lru fifo
PREP=prep_backing_menor caso_erro backing_65535_bytes "BACKING_STORE.bin: tamanho invalido (esperado 65536 bytes)" "$(arq ok)" lru fifo
PREP=prep_backing_maior caso_erro backing_65537_bytes "BACKING_STORE.bin: tamanho invalido (esperado 65536 bytes)" "$(arq ok)" lru fifo
PREP=prep_backing_link_quebrado caso_erro backing_link_quebrado "BACKING_STORE.bin: arquivo nao existe" "$(arq ok)" lru fifo
PREP=prep_backing_link_valido caso_ok backing_link_valido "$(arq ok)" lru fifo
if [ "$(id -u)" -eq 0 ]; then
    pulado backing_sem_permissao "executando como root"
else
    PREP=prep_backing_sem_permissao caso_erro backing_sem_permissao "BACKING_STORE.bin: sem permissao de leitura" "$(arq ok)" lru fifo
fi
PREP=prep_sem_backing caso_erro enderecos_antes_do_backing "arquivo de enderecos: arquivo nao existe" "$(arq inexistente)" lru fifo
PREP=prep_sem_backing caso_erro enderecos_invalidos_antes_do_backing "arquivo de enderecos: linha 1: caractere invalido (0x2B)" "$(arq mais)" lru fifo

echo "Casos OK: $OK, FALHOU: $FALHOU, PULADO: $PULADO"
[ "$FALHOU" -eq 0 ]
