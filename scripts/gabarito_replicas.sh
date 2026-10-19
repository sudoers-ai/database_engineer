#!/usr/bin/env bash
# ==========================================================================
# ATALHO: faz sozinho a etapa 5 (replica1 e replica2 como replicas do
# primario). Para quem faltou na aula da etapa 5, ou quebrou as replicas e
# quer recomecar a etapa 6 ou 7 sem refazer tudo.
#
# Ele faz exatamente o que o roteiro da etapa 5 manda:
#   1. cria o usuario replicador (se faltar);
#   2. libera a replicacao no pg_hba.conf (se faltar);
#   3. para cada replica: apaga a pasta de dados, apaga o slot antigo,
#      clona o primario com pg_basebackup e liga.
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh

echo
echo -e "${N}Criando replica1 e replica2 (a etapa 5 pronta)${F}"
echo
bash scripts/esperar.sh primario >/dev/null || exit 1
if ! sql_ok=$(sql primario "SELECT NOT pg_is_in_recovery()") || [ "$sql_ok" != t ]; then
  erro "o nó primario não é o primário agora (veja make status). Este atalho parte de um primario primário."
  exit 1
fi

sql primario "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicador') THEN
    CREATE ROLE replicador WITH LOGIN REPLICATION PASSWORD 'replica123';
  END IF; END \$\$;" >/dev/null
ok "usuário replicador"

if [ "$(sql primario "SELECT count(*) FROM pg_hba_file_rules WHERE 'replicador' = ANY(user_name)")" = 0 ]; then
  docker exec -u postgres dbe_primario bash -c \
    'echo "host replication replicador samenet scram-sha-256" >> $PGDATA/pg_hba.conf'
  sql primario "SELECT pg_reload_conf()" >/dev/null
fi
ok "pg_hba.conf libera a replicação"

for r in replica1 replica2; do
  bash scripts/zerar.sh "$r" >/dev/null || exit 1
  sql primario "SELECT pg_drop_replication_slot('$r') FROM pg_replication_slots WHERE slot_name = '$r'" >/dev/null
  docker exec -u postgres "dbe_$r" bash -c \
    "pg_basebackup -h primario -U replicador -D \$PGDATA -d 'application_name=$r' -R -Xs -C -S $r" || exit 1
  docker restart "dbe_$r" >/dev/null
  bash scripts/esperar.sh "$r" >/dev/null || exit 1
  ok "$r clonado e ligado como réplica"
done

sleep 2
bash scripts/status.sh
