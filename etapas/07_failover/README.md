# 7️⃣ Failover e switchover

> ⬅️ Anterior: [6. Replicação síncrona](../06_replicacao_sincrona/README.md) · [README principal](../../README.md) · Etapa 7 de 10

> **A pergunta da diretoria:** "O servidor caiu. Quanto tempo ficamos fora?"

Na etapa 5 você montou as réplicas. Mas uma réplica parada ao lado de um
primário morto não vende nada: alguém precisa **promovê-la**. Nesta etapa
você vive o pior dia de um DBE, do começo ao fim:

1. o primário morre (**failover**: a troca não planejada);
2. o antigo primário volta sozinho e o cluster fica com **dois primários**
   (**split-brain**);
3. você reconstrói o antigo primário com o `pg_rewind`;
4. com tudo calmo, devolve o papel de primário a ele (**switchover**: a
   troca planejada).

No fim, o cluster estará exatamente como começou, mas na **timeline 3**.

> **Pré-requisito:** as duas réplicas da etapa 5 no ar e o cluster
> **assíncrono** (o fim da etapa 6). Confira com `make status`. Se não tiver
> as réplicas, `make gabarito-replicas` cria as duas.

---

## 7.1 Antes da crise: preparando o `pg_rewind`

O `pg_rewind` (seção 7.6) conecta num servidor e lê arquivos de dentro dele.
Por padrão, só superusuário pode. Em vez de usar o `sudoers`, dê ao
`replicador` **exatamente** as quatro funções de que o `pg_rewind` precisa:

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
GRANT EXECUTE ON FUNCTION pg_catalog.pg_ls_dir(text, boolean, boolean) TO replicador;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_stat_file(text, boolean) TO replicador;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text) TO replicador;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) TO replicador;

CREATE TABLE teste_failover (
    id         serial PRIMARY KEY,
    onde       text NOT NULL,
    criado_em  timestamptz DEFAULT now()
);
INSERT INTO teste_failover (onde) VALUES ('primario, antes da queda');
```

Os `GRANT`s são feitos no primário e, como tudo, **replicados** para as
réplicas. Quando uma delas virar primário, a permissão já estará lá.

---

## 7.2 A queda

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
docker kill dbe_primario
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     desligado
replica1     no ar                  réplica      1   0/18221B18   -          0        17
replica2     no ar                  réplica      1   0/18221B18   -          0        17
...
```

As réplicas estão vivas e com os dados em dia, mas **lendo de ninguém**
(`LÊ DE = -`). E são somente leitura: a loja está fora do ar.

<!-- rodar: shell falha-esperada -->
```bash
make carga t=2 n=replica1
```

```
Simulando vendas em replica1 por 2s, 100 vendas/s...
pgbench: error: client 0 script 0 aborted in command 3 query 0: ERROR:  cannot execute INSERT in a read-only transaction
...
number of transactions actually processed: 0
make: *** [Makefile:96: carga] Error 2
```

O relógio do **RTO** começou a correr.

---

## 7.3 Promovendo a `replica1`

Promover é dizer a uma réplica: "pare de esperar WAL e vire primário".

🐘 **No psql do `replica1`** (`make psql n=replica1`):

<!-- rodar: replica1 -->
```sql
SELECT pg_promote();
SELECT pg_is_in_recovery();
```

```
 pg_promote
------------
 t
(1 row)

 pg_is_in_recovery
-------------------
 f
(1 row)
```

<!-- rodar: shell -->
```bash
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     desligado
replica1     no ar                  primário     2   0/18222000   -          0        17
replica2     no ar                  réplica      1   0/18221B18   -          0        17
...
```

A `replica1` é o novo primário, na **timeline 2**. É o mesmo fenômeno do PITR
da etapa 4: ao ser promovido, o servidor começa uma **nova linha do tempo**,
e registra onde ela nasceu num arquivo de histórico:

📦 **No terminal do `replica1`** (`make bash n=replica1`):

<!-- rodar: bash-replica1 -->
```bash
cat $PGDATA/pg_wal/00000002.history
```

```
1	0/18221B18	no recovery target specified
```

"A timeline 2 saiu da timeline 1 no LSN `0/18221B18`."

A loja volta a vender:

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
INSERT INTO teste_failover (onde) VALUES ('replica1, novo primario');
SELECT * FROM teste_failover;
```

```
 id |           onde           |           criado_em
----+--------------------------+-------------------------------
  1 | primario, antes da queda | 2026-10-19 13:18:25.166799-03
 34 | replica1, novo primario  | 2026-10-19 13:18:27.11197-03
(2 rows)
```

**Por que o `id` pulou de 1 para 34?** Para não escrever no WAL a cada
`nextval()`, o PostgreSQL registra as sequências **32 valores adiantado**. A
réplica só conhece esse valor adiantado. Depois de um failover, buracos na
sequência são normais. Por isso nunca se usa `id` sequencial como "número
da nota fiscal sem buracos".

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=5 n=replica1
```

As vendas voltaram. O seu **RTO** foi o tempo entre o `docker kill` e o
`pg_promote()`: o tempo de você perceber, decidir e digitar.

---

## 7.4 A `replica2` ficou órfã

A `replica2` continua tentando ler do `primario`, que está morto. Ela precisa
passar a ler da `replica1`. Duas coisas:

**1. Um slot para ela no novo primário.** Slots não são replicados: o slot
`replica2` existia no `primario`, não na `replica1`.

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
SELECT pg_create_physical_replication_slot('replica2');
```

**2. Apontar a `replica2` para a `replica1`.** O `primary_conninfo` é
`sighup`: dá para trocar sem reiniciar.

🐘 **No psql do `replica2`** (`make psql n=replica2`):

<!-- rodar: replica2 -->
```sql
ALTER SYSTEM SET primary_conninfo = 'host=replica1 user=replicador application_name=replica2';
SELECT pg_reload_conf();
SELECT pg_sleep(2);

SELECT status, sender_host, received_tli FROM pg_stat_wal_receiver;
SELECT id, onde FROM teste_failover;
```

```
  status   | sender_host | received_tli
-----------+-------------+--------------
 streaming | replica1    |            2
(1 row)

 id |           onde
----+--------------------------
  1 | primario, antes da queda
 34 | replica1, novo primario
(2 rows)
```

A `replica2` encontrou o arquivo `00000002.history`, entendeu que a história
mudou de rumo e **pulou para a timeline 2** sozinha (é o padrão
`recovery_target_timeline = 'latest'`).

---

## 7.5 O antigo primário volta... sozinho

O servidor que morreu foi consertado e alguém o liga, sem avisar ninguém.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make ligar n=primario
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/18221B90   -          0        17
replica1     no ar                  primário     2   0/18285F60   -          1        17
replica2     no ar                  réplica      2   0/18285F60   replica1   0        17
...
```

**Dois primários.** O `primario` não sabe que foi substituído: para ele, só
houve uma queda de energia (como na etapa 1). Ele voltou aceitando escrita.
Se a aplicação ainda tiver o endereço dele, vai vender nele:

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
INSERT INTO teste_failover (onde) VALUES ('primario, voltou sozinho (split-brain!)');
SELECT * FROM teste_failover;
```

```
 id |                  onde                   |           criado_em
----+-----------------------------------------+-------------------------------
  1 | primario, antes da queda                | 2026-10-19 13:18:25.166799-03
 34 | primario, voltou sozinho (split-brain!) | 2026-10-19 13:18:36.594583-03
(2 rows)
```

Compare com a seção 7.3: existem agora **dois registros diferentes com o
`id` 34**, um em cada servidor. Troque `teste_failover` por `pedidos` e
imagine o estrago: dois clientes com o mesmo número de pedido, um estoque que
desconta duas vezes, um financeiro que não fecha.

Isso é o **split-brain**, o pior cenário de um cluster. Desligue o antigo
primário **agora**:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make parar n=primario
```

> Em produção, quem impede isso é o *fencing*: o processo de failover garante
> que o antigo primário **não pode** voltar como primário (desliga a máquina,
> corta a rede, revoga o disco). Ferramentas como Patroni fazem isso
> sozinhas. Aqui, o fencing foi você.

---

## 7.6 Reconstruindo o antigo primário com `pg_rewind`

O `primario` não pode simplesmente virar réplica da `replica1`: a história
dele **divergiu**. Ele tem, na timeline 1, um trecho de WAL que a
`replica1` nunca viu (o split-brain).

```
 timeline 1:  ────────────●──── split-brain (id 34) ───►  primario
                          │
                 0/18221B18 (promoção)
                          │
 timeline 2:              └──── id 34 (novo primário) ──►  replica1
```

Duas saídas:

* **clonar de novo** com `pg_basebackup`: copia o banco **inteiro**;
* **`pg_rewind`**: acha o ponto de divergência e copia da `replica1` **só os
  blocos que mudaram** desde ali. Num banco de 1 TB, é a diferença entre
  horas e minutos.

O `pg_rewind` exige `data_checksums` ligado (ou `wal_log_hints`), lembra da
etapa 1? É por isso.

Primeiro, um slot para o `primario` no novo primário.

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
SELECT pg_create_physical_replication_slot('primario');
```

O `pg_rewind` precisa do servidor **desligado**. Num container, desligar o
PostgreSQL é desligar o container. A saída é um terminal especial, com a
pasta de dados do nó, mas sem o PostgreSQL rodando:

🖥️ **No seu terminal:**

```bash
make bash-desligado n=primario
```

```
Terminal no nó primario DESLIGADO. Você está na pasta de dados ($PGDATA).
O PostgreSQL deste nó NÃO está rodando. Saia com: exit
```

🔌 **No terminal do `primario` desligado:**

<!-- rodar: desligado-primario -->
```bash
pg_rewind --target-pgdata=$PGDATA \
  --source-server="host=replica1 user=replicador dbname=liga_sudoers application_name=primario" \
  --write-recovery-conf --progress
```

```
pg_rewind: connected to server
pg_rewind: servers diverged at WAL location 0/18221B18 on timeline 1
pg_rewind: rewinding from last common checkpoint at 0/130000B8 on timeline 1
pg_rewind: reading source file list
pg_rewind: reading target file list
pg_rewind: reading WAL in target
pg_rewind: need to copy 151 MB (total source directory size is 203 MB)
155146/155146 kB (100%) copied
pg_rewind: creating backup label and updating control file
pg_rewind: syncing target data directory
pg_rewind: Done!
```

Leia a segunda linha: ele achou **sozinho** o mesmo LSN do arquivo
`00000002.history`. O `--write-recovery-conf` deixou o `primario` pronto para
ligar como réplica da `replica1`. Falta dizer qual slot usar:

<!-- rodar: desligado-primario -->
```bash
echo "primary_slot_name = 'primario'" >> $PGDATA/postgresql.auto.conf
grep -E "primary_conninfo|primary_slot_name" $PGDATA/postgresql.auto.conf | cut -c1-90
```

```
primary_conninfo = 'user=replicador passfile=''/var/lib/postgresql/.pgpass'' channel_bin
primary_slot_name = 'replica1'
primary_conninfo = 'user=replicador passfile=''/var/lib/postgresql/.pgpass'' channel_bin
primary_slot_name = 'primario'
```

Duas de cada? O `pg_rewind` copiou da `replica1` os arquivos de configuração
(com o `primary_conninfo` e o slot **dela**, da época em que era réplica) e
acrescentou os novos no fim. Como você viu na etapa 4, **vale a última**.

Saia (`exit`) e ligue.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make ligar n=primario
sleep 2
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  réplica      2   0/18285F60   replica1   0        17
replica1     no ar                  primário     2   0/18285F60   -          2        17
replica2     no ar                  réplica      2   0/18285F60   replica1   0        17
...
```

O antigo primário agora é réplica do novo. E o pedido do split-brain?

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT id, onde FROM teste_failover;
```

```
 id |           onde
----+--------------------------
  1 | primario, antes da queda
 34 | replica1, novo primario
(2 rows)
```

O registro do split-brain **desapareceu**: o `pg_rewind` voltou o servidor
ao ponto de divergência. Se fosse uma venda de verdade, ela estaria perdida.
(O WAL dela ainda pode estar no arquivo da etapa 4. Recuperá-la seria um
trabalho manual de PITR. Mais um motivo para que o split-brain nunca
aconteça.)

---

## 7.7 Switchover: devolvendo o posto

Tudo funciona, mas o `primario` (a máquina mais forte, digamos) virou
réplica. Numa janela calma, você faz a troca **planejada**. A diferença para o
failover é que nada se perde: o primário atual é desligado **com calma** e,
ao desligar, ele envia todo o WAL pendente às réplicas.

**1. Desligue o primário atual (`replica1`) de forma limpa.**

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make parar n=replica1
```

**2. Promova o `primario`.**

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT pg_promote();
SELECT pg_sleep(1);

SELECT slot_name FROM pg_replication_slots;
```

```
 pg_promote
------------
 t
(1 row)
...
 slot_name
-----------
(0 rows)
```

Nenhum slot: o `pg_rewind` não traz slots. Crie os das duas réplicas e
registre a troca:

<!-- rodar: primario -->
```sql
SELECT pg_create_physical_replication_slot('replica1');
SELECT pg_create_physical_replication_slot('replica2');

INSERT INTO teste_failover (onde) VALUES ('primario, de volta (switchover)');
```

**3. Aponte a `replica2` de volta para o `primario`.**

🐘 **No psql do `replica2`:**

<!-- rodar: replica2 -->
```sql
ALTER SYSTEM SET primary_conninfo = 'host=primario user=replicador application_name=replica2';
SELECT pg_reload_conf();
```

**4. Transforme a `replica1` em réplica do `primario`.**

🖥️ **No seu terminal:**

```bash
make bash-desligado n=replica1
```

🔌 **No terminal do `replica1` desligado:**

<!-- rodar: desligado-replica1 -->
```bash
pg_rewind --target-pgdata=$PGDATA \
  --source-server="host=primario user=replicador dbname=liga_sudoers application_name=replica1" \
  --write-recovery-conf --progress
echo "primary_slot_name = 'replica1'" >> $PGDATA/postgresql.auto.conf
```

```
pg_rewind: connected to server
pg_rewind: servers diverged at WAL location 0/190000A0 on timeline 2
pg_rewind: no rewind required
```

**"No rewind required"**: como a `replica1` foi desligada com calma, o
`primario` recebeu tudo o que ela tinha. Não há divergência. Num switchover
bem feito, é sempre assim. (Rodar o `pg_rewind` mesmo assim é um bom hábito:
ele confirma isso e deixa a configuração de réplica pronta.)

Saia (`exit`) e ligue.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make ligar n=replica1
sleep 2
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     3   0/19003E90   -          2        17
replica1     no ar                  réplica      3   0/19003E90   primario   0        17
replica2     no ar                  réplica      3   0/19005C08   primario   0        17
...
```

O cluster voltou à forma original, na **timeline 3**: 1 (o começo) → 2 (o
failover) → 3 (o switchover).

<!-- rodar: replica1 -->
```sql
SELECT id, onde FROM teste_failover ORDER BY id;
```

```
 id |              onde
----+---------------------------------
  1 | primario, antes da queda
 34 | replica1, novo primario
 67 | primario, de volta (switchover)
(3 rows)
```

(Mais um salto de sequência, agora no switchover.)

Um último exame, que todo DBE faz depois de uma troca de papéis: **o
arquivamento de WAL continua funcionando?** Sem ele, o PITR da etapa 4 para
de cobrir o que acontece daqui para a frente.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT pg_switch_wal();
SELECT pg_sleep(2);
SELECT last_archived_wal, failed_count FROM pg_stat_archiver;
```

```
...
    last_archived_wal     | failed_count
--------------------------+--------------
 000000030000000000000019 |            0
(1 row)
```

Arquivando, na timeline 3, sem falhas. Não era garantido: durante o
split-brain, o `primario` arquivou um segmento da timeline 1 e, depois do
`pg_rewind`, tentou arquivá-lo **de novo**. Quem deixou passar foi o
`|| cmp -s` do `archive_command` da etapa 4 (o arquivo era idêntico). Com um
`test ! -f` sozinho, o `failed_count` estaria subindo, o arquivamento estaria
travado e o `pg_wal/` do primário, enchendo.

---

## 7.8 Como a aplicação acha o primário?

Durante o failover, a aplicação precisaria trocar o endereço de `primario`
para `replica1`. Existem várias soluções (um IP virtual, um DNS, um
balanceador como HAProxy ou PgBouncer). A mais simples já vem no próprio
driver do PostgreSQL: **vários endereços** numa conexão, e a exigência de que
o servidor aceite escrita.

📦 **No terminal do `replica2`** (`make bash n=replica2`):

<!-- rodar: bash-replica2 -->
```bash
psql "postgresql://sudoers@primario,replica1,replica2/liga_sudoers?target_session_attrs=read-write" \
  -Atc "SELECT 'conectei no ' || pg_read_file('/etc/hostname')"
```

```
conectei no primario
```

O driver tentou os três endereços, na ordem, e ficou com o primeiro que
aceita escrita (`target_session_attrs=read-write`). Se o `primario` cair e a
`replica1` for promovida, a mesma conexão passa a cair na `replica1`, sem
mudar nada na aplicação. Com `target_session_attrs=standby`, é o inverso:
ótimo para mandar os relatórios para uma réplica.

---

## 7.9 O que você fez à mão, e quem faz em produção

| Passo | Você fez | Em produção (Patroni, repmgr, pg_auto_failover...) |
|---|---|---|
| Perceber a queda | olhou o `make status` | checagem automática a cada poucos segundos |
| Escolher a réplica | a `replica1`, porque sim | a mais adiantada (maior LSN) |
| Impedir o split-brain | desligou o antigo primário | *fencing* automático |
| Promover | `pg_promote()` | automático |
| Reapontar as réplicas | `ALTER SYSTEM` + slots | automático |
| Reaproveitar o antigo primário | `pg_rewind` | automático |
| Redirecionar a aplicação | conexão com vários hosts | IP virtual, DNS, HAProxy, PgBouncer |

Ferramentas fazem isso em segundos, mas **fazem exatamente o que você fez**.
Quem nunca fez à mão não entende o que a ferramenta está fazendo quando ela
falha, e um dia ela falha.

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=7
```

```
Conferindo a etapa 7 - Failover e switchover

  ✅ primario é o primário, na timeline 3
  ✅ replica1 e replica2 recebendo o WAL do primario, na timeline 3
  ✅ slots replica1 e replica2 ativos no primario
  ✅ teste_failover tem as 3 fases (antes da queda, failover, switchover) nos três nós
  ✅ o registro do split-brain não existe em nenhum nó
  ✅ arquivamento de WAL do primario em dia depois das trocas de papel

✅ Etapa 7 conferida.
```

---

# ➡️ Continue em [8. Replicação lógica](../08_replicacao_logica/README.md)
