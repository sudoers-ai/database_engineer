#!/usr/bin/env bash
# ==========================================================================
# Abre um terminal com a pasta de dados de um no DESLIGADO.
#
# Alguns comandos so podem rodar com o PostgreSQL parado (o pg_rewind e o
# principal deles). Mas, num container, parar o PostgreSQL e parar o
# container. A saida: subir um container TEMPORARIO, com o mesmo volume de
# dados e na mesma rede, so com um terminal. Ao sair (exit), ele some.
#
#   scripts/desligado.sh primario            terminal interativo
#   scripts/desligado.sh primario 'comando'  roda o comando e sai
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh
n="${1:-}"; [ -n "$n" ] || { echo "uso: make bash-desligado n=primario"; exit 1; }
no_valido "$n"
if [ "$(container "$n")" = "running" ]; then
  erro "o nó $n está LIGADO. Desligue antes: make parar n=$n"; exit 1
fi
shift
if [ $# -gt 0 ]; then
  exec docker compose --progress quiet run --rm --no-deps -T -e MODO_DESLIGADO=1 "$n" bash -eo pipefail -c "$*"
fi
echo -e "${A}Terminal no nó ${N}$n${F}${A} DESLIGADO.${F} Você está na pasta de dados (\$PGDATA)."
echo -e "${C}O PostgreSQL deste nó NÃO está rodando. Saia com: exit${F}"
exec docker compose --progress quiet run --rm --no-deps -e MODO_DESLIGADO=1 "$n" bash
