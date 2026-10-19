# 📖 Glossário

> ⬅️ [README principal](../README.md)

Os termos desta disciplina, em português claro, com a etapa em que cada um
aparece pela primeira vez.

| Termo | O que é | Etapa |
|---|---|---|
| **`application_name`** | O nome com que uma conexão se apresenta. Numa réplica, é o nome usado no `synchronous_standby_names` | 5 |
| **Arquivamento de WAL** (*WAL archiving*) | Copiar cada segmento de WAL fechado para um storage separado, com o `archive_command`. É a base do PITR | 4 |
| **`archive_timeout`** | Força o fechamento (e o arquivamento) do segmento de WAL depois de N segundos, mesmo que ele não esteja cheio. Limita o RPO | 4 |
| **Assinatura** (*subscription*) | O lado que **recebe** a replicação lógica | 8 |
| **Assíncrona** | Replicação em que o primário responde COMMIT sem esperar a réplica | 5 |
| **Backup físico** | Cópia dos arquivos do servidor (`pg_basebackup`) | 3 |
| **Backup lógico** | Cópia do banco como comandos SQL (`pg_dump`) | 2 |
| **`backup_label`** | Arquivo de um backup físico que diz ao servidor de onde começar a reaplicar o WAL | 3 |
| **`backup_manifest`** | A lista de arquivos de um backup físico, com tamanho e *checksum*, usada pelo `pg_verifybackup` | 3 |
| **Checkpoint** | O momento em que as páginas alteradas na memória são gravadas nos arquivos de dados. A recuperação de queda começa a partir do último | 1 |
| **`context`** (de uma configuração) | O que custa mudá-la: `postmaster` (reiniciar), `sighup` (recarregar), `user` (cada sessão) | 1 |
| **Crash recovery** | A recuperação automática depois de uma queda: reaplicar o WAL desde o último checkpoint | 1 |
| **`data_checksums`** | "Dígito verificador" em cada página de dados. Detecta corrupção e permite o `pg_rewind` | 1 |
| **DDL** | Comandos que mudam a estrutura: `CREATE`, `ALTER`, `DROP`. Não viajam pela replicação lógica | 8 |
| **Failover** | Troca **não planejada** de primário: o primário morreu e uma réplica é promovida | 7 |
| **Fencing** | Garantir que o antigo primário não volte a aceitar escrita depois de um failover. Evita o split-brain | 7 |
| **Hot standby** | Réplica que aceita consultas de leitura enquanto reaplica o WAL | 5 |
| **LSN** (*Log Sequence Number*) | O endereço de uma posição no WAL. Só cresce. Ex.: `0/705E348` | 1 |
| **MVCC** | O mecanismo que dá a cada transação uma "foto" consistente do banco. É o que permite o `pg_dump` rodar sem travar a loja | 2 |
| **Partição** | Cada uma das tabelas menores em que uma tabela particionada é dividida | 9 |
| **Partition pruning** | O planejador descartar as partições que não podem ter linhas da consulta | 9 |
| **`pg_hba.conf`** | A "portaria" do PostgreSQL: quem pode conectar, de onde, em qual banco e como se autentica | 5 |
| **`pg_rewind`** | Ferramenta que faz um antigo primário voltar a ser réplica, copiando só os blocos que divergiram | 7 |
| **`PGDATA`** | O diretório de dados do servidor | 1 |
| **PITR** (*Point-In-Time Recovery*) | Restaurar o banco num instante qualquer: backup físico + reaplicação do WAL arquivado até um alvo | 4 |
| **`postgresql.auto.conf`** | O arquivo de configuração que o `ALTER SYSTEM` escreve. Vale a última ocorrência de cada parâmetro | 4 |
| **Primário** | O servidor que aceita escrita | 1 |
| **Promoção** | Transformar uma réplica (ou um servidor em recuperação) em primário: `pg_promote()` | 7 |
| **Publicação** (*publication*) | O lado que **envia** a replicação lógica: a lista de tabelas | 8 |
| **Quórum** | `synchronous_standby_names = 'ANY N (...)'`: basta a confirmação de N réplicas quaisquer da lista | 6 |
| **`recovery.signal`** | Arquivo vazio que manda o servidor ligar em recuperação até um alvo e parar (PITR) | 4 |
| **`recovery_target_*`** | O alvo de um PITR: `_name`, `_time`, `_xid` ou `_lsn` | 4 |
| **Réplica** (*standby*) | Servidor que recebe o WAL do primário e o reaplica continuamente | 5 |
| **Replicação física** | Envio do WAL cru, ao vivo, para uma réplica (*streaming replication*) | 5 |
| **Replicação lógica** | Envio de mudanças de **linhas** de tabelas escolhidas, entre servidores que podem ser de versões diferentes | 8 |
| **Replication slot** | Marcador no primário que impede o descarte do WAL que um consumidor ainda não recebeu | 5 |
| **`restore_command`** | O inverso do `archive_command`: como buscar um segmento no arquivo de WAL | 4 |
| **Restore point** | Uma etiqueta com nome no WAL (`pg_create_restore_point`), usada como alvo de PITR | 4 |
| **RPO** (*Recovery Point Objective*) | Quanto dado se aceita perder num desastre | 1 |
| **RTO** (*Recovery Time Objective*) | Quanto tempo se aceita ficar fora num desastre | 1 |
| **Segmento** | Cada arquivo de 16 MB do WAL. O nome tem a timeline e a posição | 1 |
| **Sequência** | O contador que gera os `id`s. É registrada no WAL 32 valores adiantada, por isso "pula" depois de um failover. Não viaja pela replicação lógica | 7, 8 |
| **Split-brain** | Dois servidores aceitando escrita ao mesmo tempo. O pior cenário de um cluster | 7 |
| **`standby.signal`** | Arquivo vazio que manda o servidor ligar como réplica | 5 |
| **Switchover** | Troca **planejada** de primário, sem perda de dados | 7 |
| **Síncrona** | Replicação em que o primário só responde COMMIT depois que uma réplica confirma | 6 |
| **`synchronous_commit`** | O que o COMMIT espera: `off`, `local`, `remote_write`, `on` ou `remote_apply` | 6 |
| **`synchronous_standby_names`** | Quais réplicas são síncronas: `FIRST N (...)` ou `ANY N (...)` | 6 |
| **Timeline** | A "linha do tempo" do banco. Muda a cada promoção ou fim de PITR, para que histórias diferentes nunca se misturem | 4, 7 |
| **WAL** (*Write-Ahead Log*) | O diário em que o PostgreSQL registra cada mudança **antes** de fazê-la. A base de tudo nesta disciplina | 1 |
| **`wal_level`** | Quanto detalhe vai para o WAL: `minimal`, `replica` (padrão) ou `logical` | 1, 8 |
