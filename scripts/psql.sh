#!/usr/bin/env bash
# Abre o psql em um no, com uma mensagem clara se ele nao estiver no ar.
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh
n="${1:-primario}"; no_valido "$n"
estado=$(container "$n")
if [ "$estado" != "running" ]; then
  erro "o nó $n está desligado (estado: $estado). Ligue com: make ligar n=$n"; exit 1
fi
if ! tem_dados "$n"; then
  erro "o nó $n está esperando dados: ainda não há PostgreSQL rodando nele."; exit 1
fi
if ! no_ar "$n"; then
  erro "o PostgreSQL de $n ainda não aceita conexões. Veja: make logs n=$n"; exit 1
fi
exec docker exec -it "dbe_$n" psql -P pager=off -U sudoers -d liga_sudoers
