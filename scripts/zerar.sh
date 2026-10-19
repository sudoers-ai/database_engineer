#!/usr/bin/env bash
# ==========================================================================
# APAGA a pasta de dados de um no e o deixa "esperando dados" de novo.
# So vale para os nos que nascem vazios: replica1, replica2 e restauracao.
# (Para recomecar o primario, use make limpar: ele apaga TUDO.)
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh
n="${1:-}"
case "$n" in
  replica1|replica2|restauracao) ;;
  *) erro "make zerar só vale para replica1, replica2 e restauracao (você pediu: '${n}')."
     echo "     Para recomeçar o cluster inteiro do zero: make limpar && make subir"
     exit 1 ;;
esac
echo "Apagando a pasta de dados de $n..."
docker stop "dbe_$n" >/dev/null 2>&1 || true
docker compose --progress quiet run --rm --no-deps -T -e MODO_DESLIGADO=1 "$n" \
  bash -c 'find /var/lib/postgresql/data -mindepth 1 -delete' || exit 1
docker start "dbe_$n" >/dev/null
ok "$n está vazio, esperando dados."
