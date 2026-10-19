#!/usr/bin/env bash
# Funcoes e cores usadas pelos outros scripts.
V="\033[92m"; A="\033[93m"; R="\033[91m"; C="\033[90m"; N="\033[1m"; F="\033[0m"
NOS=(primario replica1 replica2 restauracao logico)

ok()    { echo -e "  ${V}✅${F} $*"; }
aviso() { echo -e "  ${A}⚠️ ${F} $*"; }
erro()  { echo -e "  ${R}❌${F} $*"; }

no_valido() {
  local n="$1"
  for x in "${NOS[@]}"; do [ "$x" = "$n" ] && return 0; done
  erro "não conheço o nó '$n'. Os nós são: ${NOS[*]}"
  exit 1
}

# estado do container: running, exited, ausente...
container() { docker inspect -f '{{.State.Status}}' "dbe_$1" 2>/dev/null || echo "ausente"; }

pasta_dados() { [ "$1" = logico ] && echo /var/lib/postgresql/18/docker || echo /var/lib/postgresql/data; }

# o no tem dados? (os nos vazios ficam "esperando dados")
tem_dados() { docker exec "dbe_$1" test -s "$(pasta_dados "$1")/PG_VERSION" 2>/dev/null; }

# o PostgreSQL do no aceita conexoes?
no_ar() { docker exec "dbe_$1" pg_isready -q -h 127.0.0.1 -U sudoers -d postgres >/dev/null 2>&1; }

# roda uma consulta e devolve so o valor (sem cabecalho)
sql() { docker exec -i "dbe_$1" psql -X -q -At -U sudoers -d liga_sudoers -c "$2" 2>/dev/null; }
