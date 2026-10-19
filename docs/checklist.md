# ✅ Checklist do aluno

> ⬅️ [README principal](../README.md)

Use este checklist para não se perder entre as etapas. Marque cada item
**somente depois de ver a evidência** correspondente. O detalhe de cada
evidência está em [validacao_evidencia.md](./validacao_evidencia.md).

### 0) Preparação do ambiente

* [ ] Segui o guia do meu sistema: [Windows](./windows.md), [Mac](./mac.md) ou [Linux](./linux.md)
* [ ] **Windows:** estou no terminal do Ubuntu (WSL), e não no PowerShell
* [ ] Docker e Docker Compose v2 instalados
* [ ] `make --version` mostra a versão do `make`
* [ ] `make verificar` terminou com **Tudo certo**
* [ ] `make subir` terminou com **Tudo no ar**
* [ ] `make status` mostra o `primario` e o `logico` no ar e os outros três **esperando dados**

### 1) Conhecer o primário

* [ ] Contei 500 pessoas, 200 produtos e 100 mil pedidos
* [ ] Achei o arquivo da tabela `pedidos` dentro do `PGDATA`
* [ ] Sei a diferença entre configuração `postmaster` e `sighup`
* [ ] Vi o LSN andar depois de um `INSERT` e li o WAL com o `pg_waldump`
* [ ] Derrubei o primário com `docker kill` e a linha gravada antes da queda sobreviveu
* [ ] Preenchi o diagnóstico de RPO e RTO de hoje

### 2) Backup lógico

* [ ] Fiz dumps nos formatos texto, custom e diretório e comparei os tamanhos
* [ ] Guardei os usuários com `pg_dumpall --globals-only`
* [ ] Restaurei a `itens_pedidos` apagada com `pg_restore -L`, com chaves e trigger
* [ ] Contei os pedidos sem item (o RPO do dump)
* [ ] `make conferir e=2` ✅

### 3) Backup físico

* [ ] Fiz o `pg_basebackup` e li o `backup_label`
* [ ] O `pg_verifybackup` aprovou o backup e reprovou a cópia adulterada
* [ ] Restaurei o backup no nó `restauracao` e ele subiu aceitando escrita
* [ ] A categoria criada depois do backup não está no `restauracao`
* [ ] `make conferir e=3` ✅

### 4) PITR

* [ ] Liguei o arquivamento e o `pg_stat_archiver` mostra 0 falhas
* [ ] Fiz um backup base com o arquivamento ligado
* [ ] Criei o ponto `antes_do_deploy` e rodei o `UPDATE` desastroso
* [ ] Restaurei até o ponto no `restauracao` (com `archive_mode = 'off'`!)
* [ ] Vi o `restauracao` na timeline 2
* [ ] Consertei os preços da produção sem perder as vendas de depois do bug
* [ ] `make conferir e=4` ✅

### 5) Replicação assíncrona

* [ ] Criei o `replicador` e liberei a replicação no `pg_hba.conf`
* [ ] Clonei a `replica1` e a `replica2` com `pg_basebackup -R -C -S`
* [ ] Vi as réplicas em `pg_stat_replication` e `pg_stat_wal_receiver`
* [ ] A réplica recusou um `INSERT`
* [ ] Vi o atraso com o `pg_wal_replay_pause()`
* [ ] Vi o slot segurando WAL com a réplica desligada
* [ ] Vi o `DROP TABLE` chegar às réplicas (réplica não é backup)
* [ ] `make conferir e=5` ✅

### 6) Replicação síncrona

* [ ] Liguei `FIRST 1` e vi `sync` e `potential`
* [ ] Com uma réplica fora, a outra assumiu
* [ ] Com as duas fora, o `INSERT` pendurou, e o `Ctrl+C` deixou a linha só no primário
* [ ] Vi a diferença entre `on` e `remote_apply`
* [ ] Medi o TPS assíncrono e síncrono
* [ ] Voltei ao assíncrono
* [ ] `make conferir e=6` ✅

### 7) Failover e switchover

* [ ] Dei as permissões do `pg_rewind` ao `replicador`
* [ ] Derrubei o primário e promovi a `replica1` (timeline 2)
* [ ] Reapontei a `replica2` para a `replica1`
* [ ] Vi o split-brain: dois registros diferentes com o mesmo `id`
* [ ] Reconstruí o `primario` com o `pg_rewind`
* [ ] Fiz o switchover de volta (timeline 3, `no rewind required`)
* [ ] Conferi que o arquivamento de WAL seguiu funcionando depois das trocas (`failed_count = 0`)
* [ ] Conectei com vários hosts e `target_session_attrs=read-write`
* [ ] `make conferir e=7` ✅

### 8) Replicação lógica

* [ ] Mudei o `wal_level` para `logical`
* [ ] Criei a publicação (sem a `auditoria_pedidos`) e a assinatura no PostgreSQL 18
* [ ] Vi vendas do 17 aparecerem no 18
* [ ] Quebrei a replicação escrevendo no destino e consertei
* [ ] Quebrei com `ALTER TABLE` e consertei
* [ ] Vi o slot lógico segurando WAL
* [ ] Ensaiei a virada: sincronizei as sequências e vendi no 18
* [ ] Desmontei o ensaio sem deixar slot órfão
* [ ] `make conferir e=8` ✅

### 9) Particionamento

* [ ] Vi o `Seq Scan` com `Rows Removed by Filter` antes de particionar
* [ ] Criei a tabela particionada e as partições mensais
* [ ] Fiz a troca com a carga rodando, sem nenhuma venda falhar
* [ ] Vi o `Subplans Removed` depois de particionar
* [ ] Comparei o WAL do `DELETE` com o do `DETACH` + `DROP`
* [ ] Arquivei a partição mais antiga em `/backup/arquivo`
* [ ] Vi a tabela particionada nas réplicas
* [ ] `make conferir e=9` ✅

### 10) Desafios

* [ ] Escolhi o meu nível em [desafios/desafios.md](../desafios/desafios.md)
* [ ] Entregáveis prontos

### Ao fim de cada aula

* [ ] `make derruba` (para os containers e **mantém** o seu progresso)
