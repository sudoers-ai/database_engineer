#!/usr/bin/env bash
# ==========================================================================
# Espera um ou mais nos aceitarem conexoes. Evita o erro classico de rodar
# um comando com o banco ainda subindo (ou ainda aplicando WAL).
#
#   scripts/esperar.sh primario logico
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh
LIMITE=180

for n in "$@"; do
  no_valido "$n"
  inicio=$(date +%s)
  avisou=0
  while true; do
    estado=$(container "$n")
    if [ "$estado" = "ausente" ]; then
      erro "o container dbe_$n não existe. Rode: make subir"; exit 1
    fi
    if [ "$estado" != "running" ]; then
      echo
      erro "o container dbe_$n parou (estado: $estado). O PostgreSQL não conseguiu subir."
      echo "     Últimas linhas do log:"
      docker logs --tail 15 "dbe_$n" 2>&1 | sed 's/^/       /'
      echo "     Consulte docs/faq.md"
      exit 1
    fi
    # pronto = aceita conexoes E nao esta no meio de uma restauracao (PITR)
    if no_ar "$n" && ! docker exec "dbe_$n" test -f "$(pasta_dados "$n")/recovery.signal" 2>/dev/null; then
      [ "$avisou" = 1 ] && echo -e "\r  ${V}✅${F} $n pronto                                  "
      break
    fi
    # replica1, replica2 e restauracao nascem vazios: nao ha o que esperar
    if [ "$n" != primario ] && [ "$n" != logico ] && ! tem_dados "$n"; then
      echo -e "\r  ${A}⏸️ ${F} $n está no ar, mas ESPERANDO DADOS (a pasta de dados está vazia).      "
      continue 2
    fi
    agora=$(date +%s)
    if [ $((agora - inicio)) -ge "$LIMITE" ]; then
      echo
      erro "$n não ficou pronto em ${LIMITE}s."
      echo "     Veja o motivo com: make logs n=$n"
      exit 1
    fi
    avisou=1
    echo -ne "\r  ${A}⏳${F} esperando $n ... ${C}$((agora - inicio))s${F}   "
    sleep 1
  done
done
