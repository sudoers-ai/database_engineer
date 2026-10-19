#!/usr/bin/env bash
# ==========================================================================
# Confere se uma etapa da trilha foi feita, olhando o ESTADO do cluster
# (e nao o que voce digitou). Nao altera nada: pode rodar quantas vezes
# quiser.
#
#   scripts/conferir.sh 5
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh

e="${1:-}"
falhas=0
passou() { ok "$*"; }
falhou() { erro "$*"; falhas=$((falhas + 1)); }

# checa uma condicao SQL que devolve 't' ou 'f'
sql_v() { [ "$(sql "$1" "$2")" = "t" ]; }

# o arquivo (ou pasta) existe no storage de backup?
existe() { docker exec dbe_primario test -e "$1" 2>/dev/null; }

precisa_no_ar() {
  for n in "$@"; do
    if ! no_ar "$n"; then
      falhou "o nó $n não está no ar (veja: make status)"
      return 1
    fi
  done
}

# a replica recebe WAL de $2, por streaming?
replica_de() {
  local r="$1" origem="$2"
  sql_v "$r" "SELECT pg_is_in_recovery() AND EXISTS (SELECT 1 FROM pg_stat_wal_receiver WHERE status = 'streaming' AND sender_host = '$origem')"
}

titulo() {
  echo
  echo -e "${N}Conferindo a etapa $e - $1${F}"
  echo
}

case "$e" in
# --------------------------------------------------------------------------
1)
  titulo "Conhecer o primário"
  echo "  A etapa 1 não muda nada no banco: a prova é saber responder às"
  echo "  perguntas do fim do roteiro (etapas/01_primario/README.md)."
  precisa_no_ar primario && passou "primario no ar"
  ;;
# --------------------------------------------------------------------------
2)
  titulo "Backup lógico"
  for f in liga_sudoers.sql liga_sudoers.dump liga_sudoers_dir globais.sql; do
    case "$f" in
      *.sql) [ "$f" = globais.sql ] && rotulo="usuários e senhas" || rotulo="dump em formato texto" ;;
      *.dump) rotulo="dump em formato custom" ;;
      *) rotulo="dump em formato diretório" ;;
    esac
    if existe "/backup/dumps/$f"; then passou "$rotulo: /backup/dumps/$f"
    else falhou "$rotulo: falta /backup/dumps/$f (seção 2.1 / 2.3)"; fi
  done
  if precisa_no_ar primario; then
    if ! sql_v primario "SELECT to_regclass('itens_pedidos') IS NOT NULL"; then
      falhou "a tabela itens_pedidos não existe: restaure-a (seção 2.6)"
    else
      pk=$(sql primario "SELECT count(*) FROM pg_constraint WHERE conrelid = 'itens_pedidos'::regclass AND contype = 'p'")
      fk=$(sql primario "SELECT count(*) FROM pg_constraint WHERE conrelid = 'itens_pedidos'::regclass AND contype = 'f'")
      tg=$(sql primario "SELECT count(*) FROM pg_trigger WHERE tgrelid = 'itens_pedidos'::regclass AND NOT tgisinternal")
      if [ "$pk" = 1 ] && [ "$tg" = 1 ] && [ "$fk" -ge 1 ]; then
        passou "itens_pedidos restaurada com chave primária, trigger e $fk chaves estrangeiras"
      else
        falhou "itens_pedidos voltou incompleta (PK: $pk, trigger: $tg, FKs: $fk). Use pg_restore -L (seção 2.6)"
      fi
    fi
    if sql_v primario "SELECT NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'liga_sudoers_copia')"; then
      passou "banco de cópia removido"
    else
      falhou "o banco liga_sudoers_copia ainda existe (seção 2.8: dropdb)"
    fi
  fi
  ;;
# --------------------------------------------------------------------------
3)
  titulo "Backup físico"
  if existe /backup/base/etapa3/backup_label && existe /backup/base/etapa3/backup_manifest; then
    passou "backup físico em /backup/base/etapa3 (com backup_label e backup_manifest)"
  else
    falhou "falta o backup físico em /backup/base/etapa3 (seção 3.2)"
  fi
  if existe /backup/base/etapa3_tar/base.tar.gz; then
    passou "backup compactado em /backup/base/etapa3_tar"
  else
    falhou "falta o backup compactado em /backup/base/etapa3_tar (seção 3.5)"
  fi
  tl3=$(sql restauracao "SELECT timeline_id FROM pg_control_checkpoint()" || echo "")
  if [ "${tl3:-1}" -ge 2 ] 2>/dev/null; then
    passou "restauracao já foi reaproveitado no PITR da etapa 4 (timeline $tl3): a restauração da etapa 3 ficou para trás"
  elif precisa_no_ar primario restauracao; then
    if sql_v restauracao "SELECT NOT pg_is_in_recovery()"; then
      passou "restauracao no ar, restaurado do backup e aceitando escrita"
    else
      falhou "restauracao ainda está em recuperação"
    fi
    nr=$(sql restauracao "SELECT count(*) FROM categorias")
    np=$(sql primario "SELECT count(*) FROM categorias")
    if sql_v primario "SELECT EXISTS (SELECT 1 FROM categorias WHERE descricao = 'Criada depois do backup físico')" \
       && ! sql_v restauracao "SELECT EXISTS (SELECT 1 FROM categorias WHERE descricao = 'Criada depois do backup físico')"; then
      passou "restauracao tem $nr categorias e o primario $np: o backup é de antes da categoria nova"
    else
      falhou "a categoria 'Criada depois do backup físico' deveria existir só no primario (seção 3.6)"
    fi
  fi
  ;;
# --------------------------------------------------------------------------
4)
  titulo "PITR"
  if precisa_no_ar primario; then
    if sql_v primario "SELECT current_setting('archive_mode') = 'on'"; then
      arq=$(sql primario "SELECT archived_count FROM pg_stat_archiver")
      if sql_v primario "SELECT last_failed_time IS NULL OR last_archived_time > last_failed_time FROM pg_stat_archiver"; then
        passou "arquivamento ligado e sem falhas ($arq segmentos arquivados)"
      else
        falhou "o arquivamento está FALHANDO: veja pg_stat_archiver e make logs n=primario"
      fi
    else
      falhou "archive_mode não está ligado no primario (seção 4.2)"
    fi
  fi
  if existe /backup/base/pitr/backup_label; then
    passou "backup base com arquivamento em /backup/base/pitr"
  else
    falhou "falta o backup base em /backup/base/pitr (seção 4.3)"
  fi
  if precisa_no_ar primario restauracao; then
    tl=$(sql restauracao "SELECT timeline_id FROM pg_control_checkpoint()")
    if sql_v restauracao "SELECT NOT pg_is_in_recovery()" && [ "${tl:-1}" -ge 2 ] \
       && sql_v restauracao "SELECT count(*) = 0 FROM itens_pedidos WHERE valor_total <= 0.03"; then
      passou "restauracao recuperado até um ponto anterior ao deploy (timeline $tl)"
    else
      falhou "restauracao não foi recuperado até antes do deploy (seção 4.7)"
    fi
    sp=$(sql primario "SELECT sum(valor_unit) FROM produtos")
    sr=$(sql restauracao "SELECT sum(valor_unit) FROM produtos")
    if [ -n "$sp" ] && [ "$sp" = "$sr" ] && sql_v primario "SELECT min(valor_unit) > 0.01 FROM produtos"; then
      passou "preços da produção iguais aos do restauracao (soma $sp)"
    else
      falhou "os preços da produção ($sp) não batem com os do restauracao ($sr) (seção 4.9)"
    fi
    pp=$(sql primario "SELECT count(*) FROM pedidos")
    pr=$(sql restauracao "SELECT count(*) FROM pedidos")
    if [ "${pp:-0}" -gt "${pr:-0}" ]; then
      passou "as vendas de depois do bug continuam na produção ($((pp - pr)) a mais que no restauracao)"
    else
      falhou "a produção deveria ter mais pedidos que o restauracao"
    fi
  fi
  ;;
# --------------------------------------------------------------------------
5)
  titulo "Replicação assíncrona"
  if precisa_no_ar primario; then
    if sql_v primario "SELECT rolreplication AND NOT rolsuper FROM pg_roles WHERE rolname = 'replicador'"; then
      passou "usuário replicador existe, com REPLICATION e sem superusuário"
    else
      falhou "falta o usuário replicador com REPLICATION (seção 5.1)"
    fi
    if sql_v primario "SELECT EXISTS (SELECT 1 FROM pg_hba_file_rules WHERE 'replication' = ANY(database) AND 'replicador' = ANY(user_name))"; then
      passou "pg_hba.conf libera a replicação para o replicador"
    else
      falhou "falta a linha do replicador no pg_hba.conf (seção 5.1)"
    fi
  fi
  for r in replica1 replica2; do
    if precisa_no_ar "$r"; then
      if replica_de "$r" primario; then
        passou "$r é réplica e está recebendo o WAL do primario (streaming)"
      else
        falhou "$r não está recebendo o WAL do primario (seções 5.2 e 5.4)"
      fi
    fi
  done
  if no_ar primario; then
    if sql_v primario "SELECT count(*) = 2 FROM pg_replication_slots WHERE slot_name IN ('replica1', 'replica2') AND active"; then
      passou "slots replica1 e replica2 ativos no primario"
    else
      falhou "os slots replica1 e replica2 deveriam existir e estar ativos no primario"
    fi
    np=$(sql primario "SELECT count(*) FROM teste_replicacao" || echo "")
    if [ -n "$np" ]; then
      iguais=1
      for r in replica1 replica2; do
        [ "$(sql "$r" "SELECT count(*) FROM teste_replicacao")" = "$np" ] || iguais=0
      done
      [ "$iguais" = 1 ] && passou "teste_replicacao igual nos três nós ($np linhas)" \
                        || falhou "teste_replicacao diferente entre os nós"
    else
      falhou "a tabela teste_replicacao não existe (seção 5.3)"
    fi
  fi
  ;;
# --------------------------------------------------------------------------
6)
  titulo "Replicação síncrona"
  if precisa_no_ar primario; then
    faltam=$(sql primario "SELECT count(*) FROM (VALUES ('sincrono FIRST 1'), ('sincrono ANY 1'),
               ('sincrono, nenhuma replica no ar'), ('remote_apply, replay congelado')) v(m)
             WHERE NOT EXISTS (SELECT 1 FROM teste_replicacao t WHERE t.modo = v.m)")
    if [ "$faltam" = 0 ]; then
      passou "teste_replicacao tem as linhas de todos os testes (FIRST, ANY, nenhuma réplica, remote_apply)"
    else
      falhou "faltam $faltam testes em teste_replicacao (seções 6.1 a 6.5)"
    fi
    np=$(sql primario "SELECT count(*) FROM teste_replicacao")
    iguais=1
    for r in replica1 replica2; do
      [ "$(sql "$r" "SELECT count(*) FROM teste_replicacao")" = "$np" ] || iguais=0
    done
    [ "$iguais" = 1 ] && passou "as linhas chegaram às duas réplicas, inclusive a gravada sem réplica no ar" \
                      || falhou "as réplicas não têm as mesmas linhas de teste_replicacao que o primario"
    if sql_v primario "SELECT current_setting('synchronous_standby_names') = ''"; then
      passou "synchronous_standby_names vazio: o cluster voltou ao assíncrono"
    else
      falhou "o cluster ainda está síncrono: rode a seção 6.7"
    fi
    if replica_de replica1 primario && replica_de replica2 primario; then
      passou "replica1 e replica2 recebendo o WAL do primario"
    else
      falhou "replica1 e replica2 deveriam estar recebendo o WAL do primario (make status)"
    fi
  fi
  ;;
# --------------------------------------------------------------------------
7)
  titulo "Failover e switchover"
  if precisa_no_ar primario replica1 replica2; then
    tl=$(sql primario "SELECT ('x' || substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int" 2>/dev/null)
    if sql_v primario "SELECT NOT pg_is_in_recovery()" && [ "${tl:-0}" -ge 3 ]; then
      passou "primario é o primário, na timeline $tl"
    else
      falhou "o primario deveria ser o primário, na timeline 3 ou maior (seção 7.7)"
    fi
    if replica_de replica1 primario && replica_de replica2 primario; then
      passou "replica1 e replica2 recebendo o WAL do primario, na timeline $tl"
    else
      falhou "replica1 e replica2 deveriam ler do primario (seção 7.7)"
    fi
    if sql_v primario "SELECT count(*) = 2 FROM pg_replication_slots WHERE slot_name IN ('replica1', 'replica2') AND active"; then
      passou "slots replica1 e replica2 ativos no primario"
    else
      falhou "faltam os slots replica1 e replica2 no primario (seção 7.7)"
    fi
    ok3=1; sb=0
    for n in primario replica1 replica2; do
      fases=$(sql "$n" "SELECT count(DISTINCT onde) FROM teste_failover WHERE onde IN
               ('primario, antes da queda', 'replica1, novo primario', 'primario, de volta (switchover)')")
      [ "$fases" = 3 ] || ok3=0
      [ "$(sql "$n" "SELECT count(*) FROM teste_failover WHERE onde LIKE '%split-brain%'")" = 0 ] || sb=1
    done
    [ "$ok3" = 1 ] && passou "teste_failover tem as 3 fases (antes da queda, failover, switchover) nos três nós" \
                   || falhou "teste_failover deveria ter as 3 fases nos três nós"
    [ "$sb" = 0 ] && passou "o registro do split-brain não existe em nenhum nó" \
                  || falhou "o registro do split-brain ainda existe em algum nó: o pg_rewind foi feito? (seção 7.6)"
    if sql_v primario "SELECT current_setting('archive_mode') = 'on'"; then
      if sql_v primario "SELECT last_failed_time IS NULL OR last_archived_time > last_failed_time FROM pg_stat_archiver"; then
        passou "arquivamento de WAL do primario em dia depois das trocas de papel"
      else
        falhou "o arquivamento do primario está FALHANDO depois das trocas de papel (seção 7.7 e docs/faq.md)"
      fi
    fi
  fi
  ;;
# --------------------------------------------------------------------------
8)
  titulo "Replicação lógica"
  if precisa_no_ar primario logico; then
    if sql_v primario "SELECT current_setting('wal_level') = 'logical'"; then
      passou "primario com wal_level = logical"
    else
      falhou "wal_level do primario não é logical (seção 8.1)"
    fi
    v=$(sql logico "SELECT current_setting('server_version_num')::int / 10000")
    nl=$(sql logico "SELECT count(*) FROM pedidos")
    if [ "$v" = 18 ] && [ "${nl:-0}" -ge 100000 ]; then
      passou "logico é PostgreSQL 18 e recebeu os pedidos do primario ($nl)"
    else
      falhou "o logico deveria ter os pedidos do primario (seção 8.4)"
    fi
    if sql_v logico "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'produtos' AND column_name = 'estoque')"; then
      passou "produtos.estoque existe no logico (o DDL foi aplicado nos dois lados)"
    else
      falhou "falta a coluna produtos.estoque no logico (seção 8.7)"
    fi
    if sql_v logico "SELECT last_value >= (SELECT max(id) FROM pedidos) FROM pedidos_id_seq"; then
      passou "sequências do logico sincronizadas (pedidos_id_seq à frente do maior id)"
    else
      falhou "a sequência pedidos_id_seq do logico está atrás dos dados (seção 8.9)"
    fi
    if sql_v logico "SELECT NOT EXISTS (SELECT 1 FROM pg_subscription)" \
       && sql_v primario "SELECT NOT EXISTS (SELECT 1 FROM pg_publication)" \
       && sql_v primario "SELECT NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_type = 'logical')"; then
      passou "ensaio desmontado: sem assinatura no logico, sem publicação e sem slot lógico no primario"
    else
      falhou "sobrou assinatura, publicação ou slot lógico (seção 8.9: desmontando o ensaio)"
    fi
  fi
  ;;
# --------------------------------------------------------------------------
9)
  titulo "Particionamento"
  if precisa_no_ar primario; then
    np=$(sql primario "SELECT count(*) FROM pg_inherits WHERE inhparent = to_regclass('pedidos')")
    if sql_v primario "SELECT relkind = 'p' FROM pg_class WHERE oid = to_regclass('pedidos')" \
       && sql_v primario "SELECT pg_get_partkeydef('pedidos'::regclass) = 'RANGE (dt_venda)'"; then
      passou "pedidos é uma tabela particionada por faixa de dt_venda ($np partições)"
    else
      falhou "pedidos ainda não é particionada por RANGE (dt_venda) (seções 9.4 e 9.5)"
    fi
    if sql_v primario "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pedidos_pkey' AND conrelid = to_regclass('pedidos'))" \
       && sql_v primario "SELECT EXISTS (SELECT 1 FROM pg_index x JOIN pg_attribute a ON a.attrelid = x.indrelid AND a.attnum = x.indkey[0]
                                         WHERE x.indrelid = to_regclass('pedidos') AND a.attname = 'id_pessoa')"; then
      passou "chave primária pedidos_pkey (id, dt_venda) e índice em id_pessoa"
    else
      falhou "faltam a chave primária pedidos_pkey ou o índice em id_pessoa (seções 9.6 e 9.9)"
    fi
    if sql_v primario "SELECT to_regclass('pedidos_default') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pedidos_default)"; then
      passou "partição DEFAULT vazia"
    else
      falhou "a partição pedidos_default não existe ou não está vazia"
    fi
    arq=$(docker exec dbe_primario bash -c 'ls /backup/arquivo/pedidos_*.dump 2>/dev/null | head -1')
    if [ -n "$arq" ]; then
      t=$(basename "$arq" .dump)
      if sql_v primario "SELECT to_regclass('$t') IS NULL"; then
        passou "a partição mais antiga foi arquivada em /backup/arquivo e removida"
      else
        falhou "$t foi arquivada, mas ainda existe no banco (seção 9.7)"
      fi
    else
      falhou "nenhuma partição arquivada em /backup/arquivo (seção 9.7)"
    fi
    if sql_v primario "SELECT to_regclass('pedidos_legado') IS NULL"; then
      passou "pedidos_legado removida"
    else
      falhou "pedidos_legado ainda existe (seção 9.9)"
    fi
    rep=1
    for r in replica1 replica2; do
      no_ar "$r" && sql_v "$r" "SELECT relkind = 'p' FROM pg_class WHERE oid = to_regclass('pedidos')" || rep=0
    done
    [ "$rep" = 1 ] && passou "replica1 e replica2 também enxergam pedidos particionada" \
                   || falhou "as réplicas deveriam enxergar pedidos particionada (estão no ar? make status)"
  fi
  ;;
# --------------------------------------------------------------------------
*)
  echo "uso: make conferir e=N   (N de 1 a 9)"
  exit 1
  ;;
esac

echo
if [ "$falhas" -gt 0 ]; then
  echo -e "${R}❌ Etapa $e: $falhas pendência(s).${F} O roteiro está em etapas/ e as dúvidas comuns em docs/faq.md"
  echo
  exit 1
fi
echo -e "${V}✅ Etapa $e conferida.${F}"
echo
