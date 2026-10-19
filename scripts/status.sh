#!/usr/bin/env bash
# ==========================================================================
# Mostra o estado de cada no do cluster, do ponto de vista de um DBA:
#   - o container esta no ar? o PostgreSQL aceita conexoes?
#   - ele e PRIMARIO (aceita escrita) ou REPLICA (so leitura)?
#   - em que TIMELINE e em que posicao do WAL (LSN) ele esta?
#   - de quem ele recebe o WAL? quantas replicas estao ligadas nele?
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh

CONSULTA="
SELECT
  CASE WHEN NOT pg_is_in_recovery() THEN 'primário'
       WHEN (pg_stat_file('standby.signal', true)).modification IS NOT NULL THEN 'réplica'
       ELSE 'recuperando' END,
  CASE WHEN pg_is_in_recovery()
       THEN coalesce((SELECT received_tli FROM pg_stat_wal_receiver),
                     (SELECT timeline_id FROM pg_control_checkpoint()))
       ELSE ('x' || substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int END,
  CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END,
  coalesce((SELECT sender_host FROM pg_stat_wal_receiver WHERE status = 'streaming'), '-'),
  (SELECT count(*) FROM pg_stat_replication),
  current_setting('server_version_num')::int / 10000"

# cabecalho escrito ja alinhado: o printf conta bytes, e os acentos ocupam 2
echo
echo -e "${N}NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG${F}"
for n in "${NOS[@]}"; do
  estado=$(container "$n")
  if [ "$estado" = "ausente" ]; then
    printf "%-12s ${C}%-22s${F}\n" "$n" "não criado (make subir)"
  elif [ "$estado" != "running" ]; then
    printf "%-12s ${R}%-22s${F}\n" "$n" "desligado"
  elif ! tem_dados "$n"; then
    printf "%-12s ${A}%-22s${F}\n" "$n" "esperando dados"
  elif ! no_ar "$n"; then
    printf "%-12s ${A}%-22s${F}\n" "$n" "iniciando..."
  else
    IFS='|' read -r papel tl lsn origem replicas versao <<< "$(sql "$n" "$CONSULTA")"
    # "primário" e "réplica" tem acento: 1 espaco a mais de largura no printf
    printf "%-12s ${V}%-22s${F} %-13s %-3s %-12s %-10s %-8s %-3s\n" \
      "$n" "no ar" "$papel" "$tl" "$lsn" "$origem" "$replicas" "$versao"
  fi
done
echo
