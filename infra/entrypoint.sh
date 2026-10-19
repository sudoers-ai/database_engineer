#!/usr/bin/env bash
# ==========================================================================
# Entrypoint de TODOS os nos do cluster.
#
# Ele faz tres coisas antes de entregar o controle ao entrypoint oficial
# da imagem do PostgreSQL (docker-entrypoint.sh):
#
#  1. Prepara a pasta /backup, que e um volume COMPARTILHADO entre os nos.
#     E nela que ficam os dumps, os backups fisicos e o arquivo de WAL.
#
#  2. Cria o ~/.pgpass do usuario postgres. Assim os comandos que conectam
#     em outro no (pg_basebackup, pg_rewind, psql -h ...) nao pedem senha.
#     Em producao e assim que se faz: senha em arquivo protegido, nunca na
#     linha de comando.
#
#  3. Nos nos com ESPERAR_DADOS=1 (replica1, replica2, restauracao): se a
#     pasta de dados estiver VAZIA, o container fica no ar SEM PostgreSQL,
#     esperando voce preencher a pasta (com pg_basebackup ou com um backup).
#     Depois e so reiniciar o container que o PostgreSQL sobe.
#     O no NAO roda initdb: um servidor novo e vazio nao serviria de replica.
#
#  Com MODO_DESLIGADO=1 (usado por `make bash-desligado`) ele so abre um
#  terminal como usuario postgres, com a pasta de dados montada e o
#  PostgreSQL DESLIGADO. E assim que se roda o pg_rewind.
# ==========================================================================
set -e

mkdir -p /backup
chown postgres:postgres /backup
chmod 0750 /backup

PGPASS=/var/lib/postgresql/.pgpass
cat > "$PGPASS" <<'EOF'
*:*:*:sudoers:password
*:*:*:replicador:replica123
EOF
chown postgres:postgres "$PGPASS"
chmod 0600 "$PGPASS"

if [ "${MODO_DESLIGADO:-0}" = "1" ]; then
  cd "$PGDATA" 2>/dev/null || cd /
  exec gosu postgres "$@"
fi

if [ "${ESPERAR_DADOS:-0}" = "1" ] && [ ! -s "$PGDATA/PG_VERSION" ]; then
  mkdir -p "$PGDATA"
  chown postgres:postgres "$PGDATA"
  chmod 0700 "$PGDATA"
  echo "------------------------------------------------------------------"
  echo " $(hostname): a pasta de dados ($PGDATA) esta VAZIA."
  echo " O PostgreSQL NAO foi iniciado. Este no esta esperando dados:"
  echo "   - uma replica recebe os dados com pg_basebackup (etapa 5);"
  echo "   - o no de restauracao recebe um backup (etapas 3 e 4)."
  echo " Depois de preencher a pasta, reinicie o container."
  echo "------------------------------------------------------------------"
  # fica no ar, mas responde ao `docker stop` na hora
  trap 'exit 0' TERM INT
  sleep infinity &
  wait $!
  exit 0
fi

exec docker-entrypoint.sh "$@"
