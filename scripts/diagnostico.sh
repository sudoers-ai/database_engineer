#!/usr/bin/env bash
# ==========================================================================
# Junta, num relatorio so, tudo que o instrutor precisa para te ajudar.
# Copie a saida inteira e mande para ele.
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh
linha() { echo; echo "==================== $1 ===================="; }

linha "sistema"
uname -a
docker --version 2>&1
docker compose version 2>&1
echo "memoria do Docker: $(( $(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0) / 1024 / 1024 )) MB"
echo "commit do repositorio: $(git rev-parse --short HEAD 2>/dev/null || echo '?')"

linha "arquivo .env"
[ -f .env ] && cat .env | grep -v '^#' || echo "(sem .env - usando os padroes)"

linha "containers"
docker ps -a --filter "name=dbe_" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

linha "status do cluster"
bash scripts/status.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g'

for n in "${NOS[@]}"; do
  if no_ar "$n"; then
    linha "$n: configuracao alterada (postgresql.auto.conf) e replicacao"
    docker exec "dbe_$n" bash -c 'cat "$PGDATA/postgresql.auto.conf"' 2>&1 | grep -v '^#'
    docker exec "dbe_$n" bash -c 'ls "$PGDATA"/*.signal 2>/dev/null' 2>&1
    sql "$n" "SELECT 'replicas: ' || string_agg(application_name || '=' || state || '/' || sync_state, ', ') FROM pg_stat_replication"
    sql "$n" "SELECT 'slots: ' || string_agg(slot_name || '(' || slot_type || ', ativo=' || active || ')', ', ') FROM pg_replication_slots"
    sql "$n" "SELECT 'arquivamento: ' || archived_count || ' ok, ' || failed_count || ' falhas, ultima falha: ' || coalesce(last_failed_wal, '-') FROM pg_stat_archiver"
  fi
done

for n in "${NOS[@]}"; do
  linha "ultimas linhas do log: $n"
  docker logs --tail 20 "dbe_$n" 2>&1
done
